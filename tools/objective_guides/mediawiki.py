from __future__ import annotations

import hashlib
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable, Iterable
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any


ACCESSXI_USER_AGENT = (
    "AccessXI-objective-guide-importer/1.0 "
    "(accessibility data build; https://github.com/buu420/AccessXI)"
)

SITE_LICENSES = {
    "bg": "CC-BY-NC-SA-3.0",
    "ffxiclopedia": "CC-BY-SA-3.0",
}


class MediaWikiError(RuntimeError):
    """Raised when a source snapshot cannot be fetched completely and safely."""


@dataclass(frozen=True, slots=True)
class CategoryMember:
    page_id: int
    namespace: int
    title: str


@dataclass(frozen=True, slots=True)
class PageRevision:
    site: str
    api_url: str
    canonical_title: str
    page_id: int
    revision_id: int
    parent_revision_id: int
    revision_timestamp: str
    content: str
    aliases: tuple[str, ...] = ()

    @property
    def content_sha256(self) -> str:
        return hashlib.sha256(self.content.encode("utf-8")).hexdigest()

    @property
    def cache_key(self) -> str:
        return (
            f"{self.site}-page-{self.page_id}-revision-{self.revision_id}"
            f"-sha256-{self.content_sha256}"
        )

    @property
    def license_id(self) -> str:
        try:
            return SITE_LICENSES[self.site]
        except KeyError as error:
            raise MediaWikiError(f"No source license is declared for site {self.site!r}.") from error

    @property
    def source_url(self) -> str:
        quoted = urllib.parse.quote(self.canonical_title.replace(" ", "_"), safe="()_'!,-")
        if self.site == "bg":
            return f"https://www.bg-wiki.com/ffxi/{quoted}"
        if self.site == "ffxiclopedia":
            return f"https://ffxiclopedia.fandom.com/wiki/{quoted}"
        raise MediaWikiError(f"No source-page URL rule is declared for site {self.site!r}.")

    def to_dict(self) -> dict[str, Any]:
        return {
            "site": self.site,
            "api_url": self.api_url,
            "canonical_title": self.canonical_title,
            "page_id": self.page_id,
            "revision_id": self.revision_id,
            "parent_revision_id": self.parent_revision_id,
            "revision_timestamp": self.revision_timestamp,
            "content_sha256": self.content_sha256,
            "source_url": self.source_url,
            "license": self.license_id,
            "aliases": list(self.aliases),
            "content": self.content,
        }


Transport = Callable[[str, dict[str, str], dict[str, str], float], dict[str, Any]]


def _http_json_transport(
    api_url: str,
    params: dict[str, str],
    headers: dict[str, str],
    timeout: float,
) -> dict[str, Any]:
    url = f"{api_url}?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)


class MediaWikiClient:
    def __init__(
        self,
        site: str,
        api_url: str,
        *,
        cache_dir: Path | None = None,
        request_cache_dir: Path | None = None,
        transport: Transport | None = None,
        user_agent: str = ACCESSXI_USER_AGENT,
        timeout: float = 30.0,
        batch_size: int = 50,
        max_attempts: int = 4,
        min_request_interval: float = 0.0,
        request_cache_max_age: float = 7200.0,
    ) -> None:
        if site not in SITE_LICENSES:
            raise ValueError(f"Unsupported MediaWiki site: {site}")
        if batch_size < 1 or batch_size > 50:
            raise ValueError("MediaWiki batch_size must be between 1 and 50.")
        self.site = site
        self.api_url = api_url
        self.cache_dir = Path(cache_dir) if cache_dir is not None else None
        self.request_cache_dir = Path(request_cache_dir) if request_cache_dir is not None else None
        self.transport = transport or _http_json_transport
        self.user_agent = user_agent
        self.timeout = float(timeout)
        self.batch_size = int(batch_size)
        self.max_attempts = max(1, int(max_attempts))
        self.min_request_interval = max(0.0, float(min_request_interval))
        self.request_cache_max_age = max(0.0, float(request_cache_max_age))
        self._last_request_time = 0.0

    def _request_cache_identity(self, params: dict[str, str]) -> tuple[Path | None, str]:
        identity = json.dumps(
            {
                "site": self.site,
                "api_url": self.api_url,
                "params": params,
            },
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        digest = hashlib.sha256(identity.encode("utf-8")).hexdigest()
        path = self.request_cache_dir / f"query-{digest}.json" if self.request_cache_dir else None
        return path, identity

    def _load_cached_request(self, params: dict[str, str]) -> dict[str, Any] | None:
        path, identity = self._request_cache_identity(params)
        if path is None or not path.is_file() or self.request_cache_max_age <= 0:
            return None
        try:
            record = json.loads(path.read_text(encoding="utf-8"))
            created_unix = float(record.get("created_unix", 0))
            age = time.time() - created_unix
            payload = record.get("payload")
            valid = (
                record.get("schema_version") == 1
                and record.get("identity") == identity
                and 0 <= age <= self.request_cache_max_age
                and isinstance(payload, dict)
                and payload.get("batchcomplete") is True
                and "error" not in payload
            )
            if valid:
                return payload
        except (OSError, TypeError, ValueError):
            pass
        try:
            path.unlink(missing_ok=True)
        except OSError:
            pass
        return None

    def _cache_request(self, params: dict[str, str], payload: dict[str, Any]) -> None:
        path, identity = self._request_cache_identity(params)
        if path is None:
            return
        _atomic_json_write(
            path,
            {
                "schema_version": 1,
                "identity": identity,
                "created_unix": time.time(),
                "payload": payload,
            },
        )

    def clear_request_cache(self) -> None:
        """Clear only this client's short-lived, resumable API batch cache."""

        if self.request_cache_dir is None or not self.request_cache_dir.is_dir():
            return
        for path in self.request_cache_dir.glob("query-*.json"):
            path.unlink(missing_ok=True)

    def _query(self, params: dict[str, str]) -> dict[str, Any]:
        request_params = {
            "action": "query",
            "format": "json",
            "formatversion": "2",
            "maxlag": "5",
        }
        request_params.update({key: str(value) for key, value in params.items()})
        cached = self._load_cached_request(request_params)
        if cached is not None:
            return cached
        headers = {"User-Agent": self.user_agent, "Accept": "application/json"}
        last_error: Exception | None = None
        for attempt in range(self.max_attempts):
            try:
                since_last = time.monotonic() - self._last_request_time
                if since_last < self.min_request_interval:
                    time.sleep(self.min_request_interval - since_last)
                self._last_request_time = time.monotonic()
                payload = self.transport(self.api_url, request_params, headers, self.timeout)
                if not isinstance(payload, dict):
                    raise MediaWikiError("MediaWiki returned a non-object JSON payload.")
                if "error" in payload:
                    error = payload.get("error") or {}
                    code = error.get("code", "unknown") if isinstance(error, dict) else "unknown"
                    info = error.get("info", "request failed") if isinstance(error, dict) else str(error)
                    raise MediaWikiError(f"MediaWiki error {code}: {info}")
                if payload.get("batchcomplete") is not True:
                    raise MediaWikiError("MediaWiki response was not marked batchcomplete.")
                self._cache_request(request_params, payload)
                return payload
            except urllib.error.HTTPError as error:
                last_error = error
                retry_after = 0.0
                if error.code == 429 and error.headers is not None:
                    try:
                        retry_after = float(error.headers.get("Retry-After", "0") or 0)
                    except ValueError:
                        retry_after = 0.0
                if retry_after > 60:
                    raise MediaWikiError(
                        f"{self.site} rate limited the importer; retry after {int(retry_after)} seconds."
                    ) from error
                if attempt + 1 >= self.max_attempts:
                    break
                time.sleep(max(retry_after, min(8.0, 0.5 * (2**attempt))))
            except (MediaWikiError, OSError, ValueError, urllib.error.URLError) as error:
                last_error = error
                if attempt + 1 >= self.max_attempts:
                    break
                time.sleep(min(8.0, 0.5 * (2**attempt)))
        raise MediaWikiError(f"MediaWiki request failed after {self.max_attempts} attempts: {last_error}") from last_error

    def category_members(
        self,
        category_title: str,
        *,
        member_types: str = "page|subcat",
        namespaces: str | None = None,
    ) -> tuple[CategoryMember, ...]:
        category_title = category_title.strip()
        if not category_title:
            raise ValueError("A category title is required.")
        params = {
            "list": "categorymembers",
            "cmtitle": category_title,
            "cmtype": member_types,
            "cmlimit": "max",
        }
        if namespaces is not None:
            params["cmnamespace"] = namespaces

        members: dict[int, CategoryMember] = {}
        seen_tokens: set[str] = set()
        while True:
            payload = self._query(params)
            query = payload.get("query")
            batch = query.get("categorymembers") if isinstance(query, dict) else None
            if not isinstance(batch, list):
                raise MediaWikiError(f"Category response for {category_title!r} has no member list.")
            for raw in batch:
                if not isinstance(raw, dict):
                    raise MediaWikiError(f"Category response for {category_title!r} contains an invalid member.")
                member = CategoryMember(
                    page_id=int(raw.get("pageid", 0)),
                    namespace=int(raw.get("ns", -1)),
                    title=str(raw.get("title", "")).strip(),
                )
                if member.page_id <= 0 or not member.title:
                    raise MediaWikiError(f"Category response for {category_title!r} contains an incomplete member.")
                previous = members.get(member.page_id)
                if previous is not None and previous != member:
                    raise MediaWikiError(f"Category page ID {member.page_id} changed identity within one traversal.")
                members[member.page_id] = member

            continuation = payload.get("continue")
            if continuation is None:
                break
            if not isinstance(continuation, dict) or "cmcontinue" not in continuation:
                raise MediaWikiError(f"Category response for {category_title!r} has a truncated continuation.")
            token = str(continuation["cmcontinue"])
            if not token or token in seen_tokens:
                raise MediaWikiError(f"Category response for {category_title!r} repeated its continuation token.")
            seen_tokens.add(token)
            params["cmcontinue"] = token
            if "continue" in continuation:
                params["continue"] = str(continuation["continue"])

        return tuple(members.values())

    def fetch_pages(self, titles: Iterable[str]) -> tuple[PageRevision, ...]:
        pages, missing = self._fetch_pages(titles)
        if missing:
            raise MediaWikiError(f"MediaWiki page is missing: {missing[0]}")
        return pages

    def fetch_existing_pages(
        self,
        titles: Iterable[str],
    ) -> tuple[tuple[PageRevision, ...], tuple[str, ...]]:
        """Fetch all existing titles while reporting, rather than guessing over, misses."""

        return self._fetch_pages(titles)

    def _fetch_pages(
        self,
        titles: Iterable[str],
    ) -> tuple[tuple[PageRevision, ...], tuple[str, ...]]:
        requested = tuple(dict.fromkeys(title.strip() for title in titles if title.strip()))
        if not requested:
            return (), ()

        revisions: dict[int, PageRevision] = {}
        resolved_titles: set[str] = set()
        alias_targets: dict[str, str] = {}
        missing_titles: list[str] = []
        for start in range(0, len(requested), self.batch_size):
            batch = requested[start : start + self.batch_size]
            payload = self._query(
                {
                    "prop": "revisions",
                    "titles": "|".join(batch),
                    "redirects": "1",
                    "rvprop": "ids|timestamp|content",
                    "rvslots": "main",
                }
            )
            query = payload.get("query")
            if not isinstance(query, dict):
                raise MediaWikiError("Revision response has no query object.")

            normalized: dict[str, str] = {}
            for entry in query.get("normalized", []) or []:
                if isinstance(entry, dict):
                    normalized[str(entry.get("from", ""))] = str(entry.get("to", ""))
            redirects: dict[str, str] = {}
            for entry in query.get("redirects", []) or []:
                if isinstance(entry, dict):
                    redirects[str(entry.get("from", ""))] = str(entry.get("to", ""))
            alias_targets.update(redirects)

            raw_pages = query.get("pages")
            if not isinstance(raw_pages, list):
                raise MediaWikiError("Revision response has no page list.")
            for raw_page in raw_pages:
                if not isinstance(raw_page, dict):
                    raise MediaWikiError("Revision response contains an invalid page record.")
                title = str(raw_page.get("title", "")).strip()
                if raw_page.get("missing") is True or int(raw_page.get("pageid", 0) or 0) <= 0:
                    continue
                raw_revisions = raw_page.get("revisions")
                if not isinstance(raw_revisions, list) or len(raw_revisions) != 1:
                    raise MediaWikiError(f"MediaWiki page {title!r} has no unique current revision.")
                raw_revision = raw_revisions[0]
                slots = raw_revision.get("slots") if isinstance(raw_revision, dict) else None
                main = slots.get("main") if isinstance(slots, dict) else None
                content = main.get("content") if isinstance(main, dict) else None
                if content is None and isinstance(main, dict):
                    content = main.get("*")
                if not isinstance(content, str):
                    raise MediaWikiError(f"MediaWiki page {title!r} has no main-slot content.")
                revision = PageRevision(
                    site=self.site,
                    api_url=self.api_url,
                    canonical_title=title,
                    page_id=int(raw_page["pageid"]),
                    revision_id=int(raw_revision.get("revid", 0)),
                    parent_revision_id=int(raw_revision.get("parentid", 0)),
                    revision_timestamp=str(raw_revision.get("timestamp", "")),
                    content=content,
                )
                if revision.revision_id <= 0 or not revision.revision_timestamp:
                    raise MediaWikiError(f"MediaWiki page {title!r} has incomplete revision provenance.")
                previous = revisions.get(revision.page_id)
                if previous is not None and (
                    previous.canonical_title != revision.canonical_title
                    or previous.revision_id != revision.revision_id
                    or previous.content_sha256 != revision.content_sha256
                ):
                    raise MediaWikiError(
                        f"MediaWiki page ID {revision.page_id} produced conflicting canonical revisions."
                    )
                revisions[revision.page_id] = revision
                resolved_titles.add(title)

            for requested_title in batch:
                resolved = normalized.get(requested_title, requested_title)
                seen_aliases: set[str] = set()
                while resolved in redirects and resolved not in seen_aliases:
                    seen_aliases.add(resolved)
                    resolved = redirects[resolved]
                if resolved not in resolved_titles:
                    missing_titles.append(requested_title)

        aliases_by_target: dict[str, list[str]] = {}
        for alias, target in alias_targets.items():
            aliases_by_target.setdefault(target, []).append(alias)
        result = []
        for revision in revisions.values():
            aliases = tuple(sorted(set(aliases_by_target.get(revision.canonical_title, [])), key=str.casefold))
            result.append(replace(revision, aliases=aliases))
        return (
            tuple(sorted(result, key=lambda page: (page.canonical_title.casefold(), page.page_id))),
            tuple(dict.fromkeys(missing_titles)),
        )

    def cache_revision(self, revision: PageRevision) -> Path | None:
        if self.cache_dir is None:
            return None
        if revision.site != self.site:
            raise MediaWikiError("Cannot place a revision from another site in this client's cache.")
        directory = self.cache_dir / self.site
        directory.mkdir(parents=True, exist_ok=True)
        target = directory / f"{revision.cache_key}.json"
        _atomic_json_write(target, revision.to_dict())
        return target


def _atomic_json_write(path: Path, value: dict[str, Any]) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    serialized = json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    try:
        temporary.write_text(serialized, encoding="utf-8", newline="\n")
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def recursive_category_pages(
    client: MediaWikiClient,
    category_titles: Iterable[str],
) -> tuple[tuple[CategoryMember, ...], tuple[str, ...]]:
    """Walk a category tree without revisiting cycles and return namespace-zero pages."""

    queue = [title.strip() for title in category_titles if title.strip()]
    queued = {title.casefold() for title in queue}
    visited: list[str] = []
    pages: dict[int, CategoryMember] = {}
    while queue:
        category = queue.pop(0)
        visited.append(category)
        for member in client.category_members(category, member_types="page|subcat"):
            if member.namespace == 0:
                previous = pages.get(member.page_id)
                if previous is not None and previous.title != member.title:
                    raise MediaWikiError(
                        f"Category traversal changed page ID {member.page_id} from "
                        f"{previous.title!r} to {member.title!r}."
                    )
                pages[member.page_id] = member
            elif member.namespace == 14:
                key = member.title.casefold()
                if key not in queued:
                    queued.add(key)
                    queue.append(member.title)
    return (
        tuple(sorted(pages.values(), key=lambda page: (page.title.casefold(), page.page_id))),
        tuple(visited),
    )


def load_snapshot(
    snapshot_path: Path,
    *,
    expected_site: str | None = None,
) -> tuple[PageRevision, ...]:
    """Load and cryptographically validate a complete raw source snapshot."""

    path = Path(snapshot_path)
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise MediaWikiError(f"Could not read objective source snapshot {path}: {error}") from error
    if not isinstance(payload, dict) or payload.get("schema_version") != 1:
        raise MediaWikiError(f"Objective source snapshot {path} has an unsupported schema.")
    site = str(payload.get("site", ""))
    api_url = str(payload.get("api_url", ""))
    if expected_site is not None and site != expected_site:
        raise MediaWikiError(
            f"Objective source snapshot {path} is for {site!r}, expected {expected_site!r}."
        )
    if site not in SITE_LICENSES or payload.get("license") != SITE_LICENSES[site]:
        raise MediaWikiError(f"Objective source snapshot {path} has invalid license metadata.")
    raw_pages = payload.get("pages")
    if not isinstance(raw_pages, list) or not raw_pages:
        raise MediaWikiError(f"Objective source snapshot {path} has no pages.")

    pages: list[PageRevision] = []
    identities: set[tuple[str, int]] = set()
    for raw in raw_pages:
        if not isinstance(raw, dict):
            raise MediaWikiError(f"Objective source snapshot {path} contains an invalid page.")
        try:
            page = PageRevision(
                site=site,
                api_url=api_url,
                canonical_title=str(raw["canonical_title"]),
                page_id=int(raw["page_id"]),
                revision_id=int(raw["revision_id"]),
                parent_revision_id=int(raw.get("parent_revision_id", 0)),
                revision_timestamp=str(raw["revision_timestamp"]),
                content=str(raw["content"]),
                aliases=tuple(str(value) for value in raw.get("aliases", [])),
            )
        except (KeyError, TypeError, ValueError) as error:
            raise MediaWikiError(f"Objective source snapshot {path} has incomplete page metadata.") from error
        if page.page_id <= 0 or page.revision_id <= 0 or not page.canonical_title:
            raise MediaWikiError(f"Objective source snapshot {path} has an invalid page identity.")
        if raw.get("content_sha256") != page.content_sha256:
            raise MediaWikiError(
                f"Objective source snapshot {path} failed the content hash for {page.canonical_title!r}."
            )
        if raw.get("license") != page.license_id or raw.get("source_url") != page.source_url:
            raise MediaWikiError(
                f"Objective source snapshot {path} failed provenance validation for {page.canonical_title!r}."
            )
        identity = (site, page.page_id)
        if identity in identities:
            raise MediaWikiError(f"Objective source snapshot {path} repeats page ID {page.page_id}.")
        identities.add(identity)
        pages.append(page)
    return tuple(sorted(pages, key=lambda page: (page.canonical_title.casefold(), page.page_id)))


def refresh_snapshot(
    client: MediaWikiClient,
    titles: Iterable[str],
    snapshot_path: Path,
) -> tuple[PageRevision, ...]:
    pages = client.fetch_pages(titles)
    write_snapshot(client, pages, snapshot_path)
    return pages


def write_snapshot(
    client: MediaWikiClient,
    pages: Iterable[PageRevision],
    snapshot_path: Path,
) -> tuple[PageRevision, ...]:
    pages = tuple(sorted(pages, key=lambda page: (page.canonical_title.casefold(), page.page_id)))
    if not pages:
        raise MediaWikiError("Refusing to replace a source snapshot with no pages.")
    identities: set[int] = set()
    for page in pages:
        if page.site != client.site:
            raise MediaWikiError(
                f"Refusing to mix {page.site!r} data into the {client.site!r} snapshot."
            )
        if page.page_id in identities:
            raise MediaWikiError(f"Refusing to repeat source page ID {page.page_id} in one snapshot.")
        identities.add(page.page_id)
        client.cache_revision(page)
    payload = {
        "schema_version": 1,
        "site": client.site,
        "api_url": client.api_url,
        "license": SITE_LICENSES[client.site],
        "pages": [page.to_dict() for page in pages],
    }
    _atomic_json_write(Path(snapshot_path), payload)
    return pages
