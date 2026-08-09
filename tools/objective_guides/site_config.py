from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any, Iterable


SCHEMA_VERSION = 1
SITEINFO_QUERY = {
    "action": "query",
    "format": "json",
    "formatversion": "2",
    "maxlag": "5",
    "meta": "siteinfo",
    "siprop": "general|namespaces|namespacealiases|interwikimap",
}
EXPECTED_SITE_APIS = {
    "bg": "https://www.bg-wiki.com/api.php",
    "ffxiclopedia": "https://ffxiclopedia.fandom.com/api.php",
}


class SiteConfigError(ValueError):
    """Raised when a source wiki's link-classification policy is unavailable or invalid."""


def _prefix_key(value: object) -> str:
    return re.sub(r"\s+", " ", str(value or "").replace("_", " ")).strip().casefold()


def _canonical_json(value: object) -> str:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )


def _sha256(value: object) -> str:
    return hashlib.sha256(_canonical_json(value).encode("utf-8")).hexdigest()


def _required_text(value: object, field: str) -> str:
    text = str(value or "").strip()
    if not text:
        raise SiteConfigError(f"Source site config has no {field}.")
    return text


@dataclass(frozen=True, slots=True)
class SiteLinkPolicy:
    site: str
    api_url: str
    captured_at_utc: str
    generator: str
    wiki_id: str
    namespace_prefixes: tuple[tuple[str, int], ...]
    interwiki_prefixes: tuple[tuple[str, bool], ...]

    def namespace_id(self, prefix: object) -> int | None:
        key = _prefix_key(prefix)
        matches = {namespace_id for name, namespace_id in self.namespace_prefixes if name == key}
        if len(matches) != 1:
            return None
        return next(iter(matches))

    def is_interwiki(self, prefix: object) -> bool:
        key = _prefix_key(prefix)
        return any(name == key for name, _language in self.interwiki_prefixes)

    def is_language_interwiki(self, prefix: object) -> bool:
        key = _prefix_key(prefix)
        return any(
            name == key and language
            for name, language in self.interwiki_prefixes
        )

    def classifies_prefix(self, prefix: object) -> bool:
        return self.namespace_id(prefix) is not None or self.is_interwiki(prefix)


def _normalized_namespaces(
    raw_namespaces: object,
    raw_aliases: object,
) -> list[dict[str, Any]]:
    if not isinstance(raw_namespaces, dict) or not raw_namespaces:
        raise SiteConfigError("Siteinfo response has no complete namespace map.")
    if not isinstance(raw_aliases, list):
        raise SiteConfigError("Siteinfo response has no namespace alias list.")

    namespaces: dict[int, dict[str, Any]] = {}
    for raw_key, raw_namespace in raw_namespaces.items():
        if not isinstance(raw_namespace, dict):
            raise SiteConfigError("Siteinfo namespace entry is not an object.")
        try:
            namespace_id = int(raw_namespace.get("id", raw_key))
        except (TypeError, ValueError) as error:
            raise SiteConfigError("Siteinfo namespace has an invalid ID.") from error
        if str(raw_key) != str(namespace_id):
            raise SiteConfigError("Siteinfo namespace key and ID disagree.")
        if namespace_id in namespaces:
            raise SiteConfigError(f"Siteinfo repeats namespace ID {namespace_id}.")
        name = str(raw_namespace.get("name", raw_namespace.get("*", ""))).strip()
        canonical = str(raw_namespace.get("canonical", "")).strip()
        namespaces[namespace_id] = {
            "id": namespace_id,
            "canonical": canonical,
            "name": name,
            "aliases": [],
        }
    if 0 not in namespaces:
        raise SiteConfigError("Siteinfo namespace map has no main namespace.")

    for raw_alias in raw_aliases:
        if not isinstance(raw_alias, dict):
            raise SiteConfigError("Siteinfo namespace alias is not an object.")
        try:
            namespace_id = int(raw_alias.get("id"))
        except (TypeError, ValueError) as error:
            raise SiteConfigError("Siteinfo namespace alias has an invalid ID.") from error
        alias = str(raw_alias.get("alias", raw_alias.get("*", ""))).strip()
        if namespace_id not in namespaces or not alias:
            raise SiteConfigError("Siteinfo namespace alias is incomplete.")
        namespaces[namespace_id]["aliases"].append(alias)

    prefix_owners: dict[str, int] = {}
    result: list[dict[str, Any]] = []
    for namespace_id in sorted(namespaces):
        row = namespaces[namespace_id]
        row["aliases"] = sorted(
            dict.fromkeys(row["aliases"]),
            key=lambda value: (_prefix_key(value), value),
        )
        for prefix in (row["canonical"], row["name"], *row["aliases"]):
            key = _prefix_key(prefix)
            if not key:
                continue
            previous = prefix_owners.get(key)
            if previous is not None and previous != namespace_id:
                raise SiteConfigError(
                    f"Namespace prefix {prefix!r} maps to IDs {previous} and {namespace_id}."
                )
            prefix_owners[key] = namespace_id
        result.append(row)
    return result


def _normalized_interwiki(raw_interwiki: object) -> list[dict[str, Any]]:
    if not isinstance(raw_interwiki, list):
        raise SiteConfigError("Siteinfo response has no interwiki map.")
    result: list[dict[str, Any]] = []
    prefixes: set[str] = set()
    for raw_entry in raw_interwiki:
        if not isinstance(raw_entry, dict):
            raise SiteConfigError("Siteinfo interwiki entry is not an object.")
        prefix = _required_text(raw_entry.get("prefix"), "interwiki prefix")
        key = _prefix_key(prefix)
        if key in prefixes:
            raise SiteConfigError(f"Siteinfo repeats interwiki prefix {prefix!r}.")
        prefixes.add(key)
        language = "language" in raw_entry or "extralanglink" in raw_entry
        result.append(
            {
                "prefix": prefix,
                "language": language,
                "bcp47": str(raw_entry.get("bcp47", "")).strip(),
            }
        )
    return sorted(result, key=lambda row: (_prefix_key(row["prefix"]), row["prefix"]))


def site_config_entry_from_response(
    site: str,
    api_url: str,
    response: object,
) -> dict[str, Any]:
    expected_api = EXPECTED_SITE_APIS.get(site)
    if expected_api is None:
        raise SiteConfigError(f"Unsupported source site {site!r}.")
    if api_url != expected_api:
        raise SiteConfigError(
            f"Source site {site!r} must use its pinned API {expected_api!r}."
        )
    if not isinstance(response, dict) or response.get("batchcomplete") is not True:
        raise SiteConfigError("Siteinfo response was not marked batchcomplete.")
    query = response.get("query")
    if not isinstance(query, dict):
        raise SiteConfigError("Siteinfo response has no query object.")
    general = query.get("general")
    if not isinstance(general, dict):
        raise SiteConfigError("Siteinfo response has no general metadata.")
    captured_at = _required_text(general.get("time"), "capture timestamp")
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", captured_at) is None:
        raise SiteConfigError("Siteinfo capture timestamp is not canonical UTC.")

    namespaces = _normalized_namespaces(
        query.get("namespaces"),
        query.get("namespacealiases"),
    )
    interwiki = _normalized_interwiki(query.get("interwikimap"))
    normalized_siteinfo = {
        "general": {
            "generator": _required_text(general.get("generator"), "MediaWiki generator"),
            "time": captured_at,
            "wikiid": _required_text(general.get("wikiid"), "wiki ID"),
        },
        "namespaces": namespaces,
        "interwiki": interwiki,
    }
    return {
        "site": site,
        "api_url": api_url,
        "capture_query": dict(SITEINFO_QUERY),
        "captured_at_utc": captured_at,
        "generator": normalized_siteinfo["general"]["generator"],
        "wiki_id": normalized_siteinfo["general"]["wikiid"],
        "normalized_siteinfo_sha256": _sha256(normalized_siteinfo),
        "namespaces": namespaces,
        "interwiki": interwiki,
    }


def _validated_entry(site: str, value: object) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise SiteConfigError(f"Source site config for {site!r} is not an object.")
    if value.get("site") != site:
        raise SiteConfigError(f"Source site config key {site!r} disagrees with its site field.")
    api_url = _required_text(value.get("api_url"), f"API URL for {site}")
    if api_url != EXPECTED_SITE_APIS.get(site):
        raise SiteConfigError(f"Source site config for {site!r} has an unpinned API URL.")
    if value.get("capture_query") != SITEINFO_QUERY:
        raise SiteConfigError(f"Source site config for {site!r} has an unexpected capture query.")

    namespaces = _normalized_namespaces(
        {
            str(row.get("id")): {
                "id": row.get("id"),
                "canonical": row.get("canonical", ""),
                "name": row.get("name", ""),
            }
            for row in value.get("namespaces", [])
            if isinstance(row, dict)
        },
        [
            {"id": row.get("id"), "alias": alias}
            for row in value.get("namespaces", [])
            if isinstance(row, dict)
            for alias in row.get("aliases", [])
        ],
    )
    if namespaces != value.get("namespaces"):
        raise SiteConfigError(f"Source site config for {site!r} is not canonically ordered.")

    raw_interwiki = value.get("interwiki")
    if not isinstance(raw_interwiki, list):
        raise SiteConfigError(f"Source site config for {site!r} has no interwiki map.")
    normalized_interwiki = _normalized_interwiki(
        [
            {
                "prefix": row.get("prefix"),
                **({"language": True} if row.get("language") is True else {}),
                "bcp47": row.get("bcp47", ""),
            }
            for row in raw_interwiki
            if isinstance(row, dict)
        ]
    )
    if normalized_interwiki != raw_interwiki:
        raise SiteConfigError(f"Source site config for {site!r} is not canonically ordered.")

    captured_at = _required_text(value.get("captured_at_utc"), f"capture timestamp for {site}")
    generator = _required_text(value.get("generator"), f"MediaWiki generator for {site}")
    wiki_id = _required_text(value.get("wiki_id"), f"wiki ID for {site}")
    normalized_siteinfo = {
        "general": {
            "generator": generator,
            "time": captured_at,
            "wikiid": wiki_id,
        },
        "namespaces": namespaces,
        "interwiki": normalized_interwiki,
    }
    if value.get("normalized_siteinfo_sha256") != _sha256(normalized_siteinfo):
        raise SiteConfigError(f"Source site config for {site!r} failed its siteinfo hash.")
    return dict(value)


def build_site_config_artifact(entries: Iterable[dict[str, Any]]) -> dict[str, Any]:
    sites: dict[str, dict[str, Any]] = {}
    for raw_entry in entries:
        site = str(raw_entry.get("site", "")) if isinstance(raw_entry, dict) else ""
        if not site or site in sites:
            raise SiteConfigError("Source site config entries have a missing or duplicate site.")
        sites[site] = _validated_entry(site, raw_entry)
    ordered_sites = {site: sites[site] for site in sorted(sites)}
    payload = {"schema_version": SCHEMA_VERSION, "sites": ordered_sites}
    return {**payload, "payload_sha256": _sha256(payload)}


def _policy_from_entry(site: str, entry: dict[str, Any]) -> SiteLinkPolicy:
    namespace_prefixes: list[tuple[str, int]] = []
    for namespace in entry["namespaces"]:
        namespace_id = int(namespace["id"])
        for prefix in (
            namespace.get("canonical", ""),
            namespace.get("name", ""),
            *namespace.get("aliases", ()),
        ):
            key = _prefix_key(prefix)
            if key:
                namespace_prefixes.append((key, namespace_id))
    interwiki_prefixes = [
        (_prefix_key(row["prefix"]), bool(row["language"]))
        for row in entry["interwiki"]
    ]
    return SiteLinkPolicy(
        site=site,
        api_url=entry["api_url"],
        captured_at_utc=entry["captured_at_utc"],
        generator=entry["generator"],
        wiki_id=entry["wiki_id"],
        namespace_prefixes=tuple(sorted(set(namespace_prefixes))),
        interwiki_prefixes=tuple(sorted(set(interwiki_prefixes))),
    )


def load_site_link_policies(
    path: Path,
    *,
    required_sites: Iterable[str] = tuple(EXPECTED_SITE_APIS),
) -> dict[str, SiteLinkPolicy]:
    try:
        artifact = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise SiteConfigError(f"Could not load source site config {path}: {error}") from error
    if not isinstance(artifact, dict) or artifact.get("schema_version") != SCHEMA_VERSION:
        raise SiteConfigError("Source site config has an unsupported schema.")
    sites = artifact.get("sites")
    if not isinstance(sites, dict):
        raise SiteConfigError("Source site config has no sites object.")
    required = tuple(dict.fromkeys(str(site) for site in required_sites))
    if set(sites) != set(required):
        raise SiteConfigError(
            "Source site config must contain exactly: " + ", ".join(sorted(required)) + "."
        )
    payload = {"schema_version": SCHEMA_VERSION, "sites": sites}
    if artifact.get("payload_sha256") != _sha256(payload):
        raise SiteConfigError("Source site config failed its payload hash.")

    policies: dict[str, SiteLinkPolicy] = {}
    for site in sorted(required):
        entry = _validated_entry(site, sites[site])
        policies[site] = _policy_from_entry(site, entry)
    return policies


def default_site_config_path() -> Path:
    return Path(__file__).resolve().parents[2] / "data" / "mission-quest-guides" / "source-site-config.json"


@lru_cache(maxsize=1)
def load_default_site_link_policies() -> dict[str, SiteLinkPolicy]:
    return load_site_link_policies(default_site_config_path())


def write_site_config_artifact(path: Path, artifact: dict[str, Any]) -> None:
    validated = build_site_config_artifact(artifact.get("sites", {}).values())
    if validated != artifact:
        raise SiteConfigError("Source site config artifact is not canonical.")
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(
        json.dumps(artifact, ensure_ascii=False, indent=2, sort_keys=False) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    temporary.replace(path)
