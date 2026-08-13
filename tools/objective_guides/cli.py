from __future__ import annotations

import argparse
import hashlib
import json
import sys
import tempfile
from pathlib import Path
from typing import Any

from .generate_lua import build_guide_artifacts
from .mediawiki import (
    MediaWikiClient,
    MediaWikiError,
    PageRevision,
    load_snapshot,
    recursive_category_pages,
    write_snapshot,
)
from .model import NativeObjective
from .native_manifest import build_native_manifest
from . import route_evidence
from .site_config import (
    SiteConfigError,
    SiteLinkPolicy,
    build_site_config_artifact,
    load_site_link_policies,
    site_config_entry_from_response,
    validate_source_site_binding,
    write_site_config_artifact,
)
from .wikitext import WikitextError, parse_objective_page


SITE_CONFIG = {
    "bg": {
        "api_url": "https://www.bg-wiki.com/api.php",
        "categories": ("Category:Missions", "Category:Quests"),
        "additional_titles": (),
    },
    "ffxiclopedia": {
        "api_url": "https://ffxiclopedia.fandom.com/api.php",
        "categories": ("Category:Missions", "Category:Quests"),
        # The wiki explicitly says this miniquest is absent from the in-game
        # quest log, so it is not reachable through the normal quest category
        # traversal or the native title "The Sahagin's Key".
        "additional_titles": ("Sahagin Key Quest",),
    },
}


def _atomic_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    temporary.replace(path)


def _load_navigation_catalog(
    destinations_path: Path,
    graph_path: Path,
) -> tuple[tuple[dict[str, Any], ...], dict[int, str], tuple[dict[str, Any], ...]]:
    points: list[dict[str, Any]] = []
    for line in destinations_path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) < 7:
            raise ValueError(f"Malformed navigation destination row: {line!r}")
        try:
            zone = int(fields[0])
            x, z, y = (float(fields[index]) for index in (2, 3, 4))
            raw_spawn_ids = (
                tuple(int(value) for value in fields[11].split(","))
                if len(fields) >= 12 and fields[11].strip()
                else ()
            )
        except ValueError as error:
            raise ValueError(f"Malformed navigation destination row: {line!r}") from error
        section = fields[8].strip() if len(fields) >= 9 else ""
        points.append(
            {
                "zone": zone,
                "name": fields[1].strip(),
                "x": x,
                "z": z,
                "y": y,
                "kind": fields[5].strip(),
                "source": fields[6].strip(),
                "confidence": fields[7].strip() if len(fields) >= 8 else "",
                "section": section,
                "note": section,
                "destination_id": fields[9].strip() if len(fields) >= 10 else "",
                "raw_identity": fields[10].strip() if len(fields) >= 11 else "",
                "raw_spawn_ids": raw_spawn_ids,
                "cluster_policy_version": fields[12].strip() if len(fields) >= 13 else "",
            }
        )

    zone_names: dict[int, str] = {}
    edges: list[dict[str, Any]] = []

    def record_zone(zone_value: str, name_value: str) -> None:
        zone = int(zone_value)
        name = name_value.strip()
        previous = zone_names.get(zone)
        if previous is not None and previous.casefold() != name.casefold():
            raise ValueError(
                f"Navigation graph gives zone {zone} conflicting names {previous!r} and {name!r}."
            )
        zone_names[zone] = name

    rows = graph_path.read_text(encoding="utf-8").splitlines()
    for line in rows[1:]:
        if not line.strip():
            continue
        fields = line.split("\t")
        if len(fields) < 13:
            raise ValueError(f"Malformed navigation graph row: {line!r}")
        try:
            record_zone(fields[1], fields[2])
            record_zone(fields[7], fields[8])
        except ValueError as error:
            raise ValueError(f"Malformed navigation graph row: {line!r}") from error
        edges.append(
            {
                "id": int(fields[0]),
                "from_zone": int(fields[1]),
                "from_name": fields[2].strip(),
                "to_zone": int(fields[7]),
                "to_name": fields[8].strip(),
                "source": fields[13].strip(),
                "confidence": fields[14].strip(),
            }
        )
    return tuple(points), zone_names, tuple(edges)


def _native_payload(rows: tuple[NativeObjective, ...]) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "objectives": [
            {
                "key": row.key,
                "kind": row.kind,
                "context": row.context,
                "native_id": row.native_id,
                "progress_id": row.progress_id,
                "title": row.title,
                "details": list(row.details),
                "source_dat": row.source_dat,
                "record_offset": row.record_offset,
            }
            for row in sorted(rows, key=lambda value: value.key)
        ],
    }


def _load_overrides(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise MediaWikiError(f"Could not load reviewed overrides {path}: {error}") from error
    if not isinstance(value, dict):
        raise MediaWikiError(f"Reviewed overrides {path} must contain a JSON object.")
    return value


def _overrides_for_sites(
    overrides: dict[str, Any],
    sites: tuple[str, ...],
) -> dict[str, Any]:
    selected = set(sites)
    result = dict(overrides)
    page_matches = overrides.get("page_matches", {})
    if isinstance(page_matches, dict):
        result["page_matches"] = {
            native_key: {
                site: identity
                for site, identity in per_site.items()
                if site in selected
            }
            for native_key, per_site in page_matches.items()
            if isinstance(per_site, dict)
            and any(site in selected for site in per_site)
        }
    shared_groups = overrides.get("shared_page_groups", [])
    if isinstance(shared_groups, list):
        result["shared_page_groups"] = [
            group
            for group in shared_groups
            if isinstance(group, dict) and str(group.get("site", "")) in selected
        ]
    if not {"bg", "ffxiclopedia"}.issubset(selected):
        result["target_overrides"] = {}
    return result


def _snapshot_path(cache_root: Path, site: str) -> Path:
    return cache_root / "snapshots" / f"{site}.json"


def _requested_source_titles(
    category_titles: tuple[str, ...] | list[str],
    native_rows: tuple[NativeObjective, ...],
    additional_titles: tuple[str, ...] | list[str] = (),
) -> tuple[str, ...]:
    native_titles = (row.title for row in native_rows)
    return tuple(dict.fromkeys((*category_titles, *native_titles, *additional_titles)))


def _discover_and_fetch(
    client: MediaWikiClient,
    native_rows: tuple[NativeObjective, ...],
) -> tuple[tuple[PageRevision, ...], dict[str, Any]]:
    config = SITE_CONFIG[client.site]
    category_pages, categories = recursive_category_pages(client, config["categories"])
    category_titles = [page.title for page in category_pages]
    requested_titles = _requested_source_titles(
        category_titles,
        native_rows,
        config.get("additional_titles", ()),
    )
    pages, missing = client.fetch_existing_pages(requested_titles)
    fetched_titles = {
        title.casefold()
        for page in pages
        for title in (page.canonical_title, *page.aliases)
    }
    omitted_category_pages = sorted(
        page.title for page in category_pages if page.title.casefold() not in fetched_titles
    )
    if omitted_category_pages:
        raise MediaWikiError(
            f"{client.site} did not return {len(omitted_category_pages)} discovered category pages."
        )
    discovery = {
        "site": client.site,
        "root_categories": list(config["categories"]),
        "visited_categories": list(categories),
        "category_page_count": len(category_pages),
        "requested_title_count": len(requested_titles),
        "fetched_page_count": len(pages),
        "missing_native_title_candidates": list(missing),
    }
    return pages, discovery


def _source_pages(
    native_rows: tuple[NativeObjective, ...],
    *,
    cache_root: Path,
    offline: bool,
    refresh: bool,
    sites: tuple[str, ...],
) -> tuple[tuple[PageRevision, ...], dict[str, Any]]:
    if offline and refresh:
        raise MediaWikiError("--offline refuses network access and cannot be combined with --refresh.")

    all_pages: list[PageRevision] = []
    discovery: dict[str, Any] = {"schema_version": 1, "sites": {}}
    for site in sites:
        config = SITE_CONFIG[site]
        snapshot = _snapshot_path(cache_root, site)
        discovery_path = cache_root / "snapshots" / f"{site}-discovery.json"
        if snapshot.is_file() and not refresh:
            pages = load_snapshot(snapshot, expected_site=site)
            if discovery_path.is_file():
                try:
                    site_discovery = json.loads(discovery_path.read_text(encoding="utf-8"))
                except (OSError, ValueError) as error:
                    raise MediaWikiError(f"Could not load discovery metadata {discovery_path}: {error}") from error
            else:
                site_discovery = {
                    "site": site,
                    "fetched_page_count": len(pages),
                    "snapshot_reused": True,
                }
        else:
            if offline:
                raise MediaWikiError(f"Offline source snapshot is missing: {snapshot}")
            client = MediaWikiClient(
                site,
                str(config["api_url"]),
                cache_dir=cache_root / "revisions",
                request_cache_dir=cache_root / "resume" / site,
                min_request_interval=0.2,
            )
            pages, site_discovery = _discover_and_fetch(client, native_rows)
            write_snapshot(client, pages, snapshot)
            _atomic_json(discovery_path, site_discovery)
            client.clear_request_cache()
        all_pages.extend(pages)
        discovery["sites"][site] = site_discovery
    return tuple(all_pages), discovery


def _capture_source_site_config(cache_root: Path) -> dict[str, Any]:
    entries: list[dict[str, Any]] = []
    for site, config in SITE_CONFIG.items():
        api_url = str(config["api_url"])
        client = MediaWikiClient(
            site,
            api_url,
            request_cache_dir=cache_root / "resume" / "site-config" / site,
            min_request_interval=0.2,
            request_cache_max_age=0.0,
        )
        response = client.site_info()
        entries.append(site_config_entry_from_response(site, api_url, response))
        client.clear_request_cache()
    return build_site_config_artifact(entries)


def _parse_pages(
    source_pages: tuple[PageRevision, ...],
    *,
    site_policies: dict[str, SiteLinkPolicy],
) -> tuple[tuple[Any, ...], tuple[dict[str, Any], ...]]:
    for site, policy in site_policies.items():
        if not isinstance(policy, SiteLinkPolicy):
            raise SiteConfigError(f"Source site policy for {site!r} has an invalid type.")
        validate_source_site_binding(site, policy.api_url, policy)
    missing = sorted({page.site for page in source_pages if page.site not in site_policies})
    if missing:
        raise SiteConfigError(
            "Source site config has no policy for revision site(s): "
            + ", ".join(missing)
            + "."
        )
    for page in source_pages:
        validate_source_site_binding(
            page.site,
            page.api_url,
            site_policies[page.site],
        )
    parsed = []
    failures = []
    for page in sorted(source_pages, key=lambda value: (value.site, value.page_id)):
        try:
            parsed.append(parse_objective_page(page, site_policy=site_policies[page.site]))
        except (WikitextError, ValueError) as error:
            failures.append(
                {
                    "site": page.site,
                    "page_id": page.page_id,
                    "revision_id": page.revision_id,
                    "title": page.canonical_title,
                    "source_url": page.source_url,
                    "reason": str(error)[:500],
                }
            )
    return tuple(parsed), tuple(failures)


def _print_report(data_root: Path) -> None:
    coverage_path = data_root / "coverage.json"
    if not coverage_path.is_file():
        raise MediaWikiError(f"Coverage report is unavailable: {coverage_path}")
    coverage = json.loads(coverage_path.read_text(encoding="utf-8"))
    counts = coverage.get("counts", {})
    print(f"Valid native objectives: {counts.get('valid_native', 0)}")
    for status, count in sorted(counts.get("by_status", {}).items()):
        print(f"{status}: {count}")
    print(f"Dual-source matches: {counts.get('dual_source', 0)}")


def _atomic_bytes(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    try:
        temporary.write_bytes(payload)
        temporary.replace(path)
    except OSError:
        temporary.unlink(missing_ok=True)
        raise


def _build_route_artifacts(
    *,
    repo_root: Path,
    data_root: Path,
    route_inputs: dict[str, Any],
    third_party_root: Path,
    refresh: bool,
    runtime_ready: bool,
    update_runtime_pin_path: Path | None,
) -> dict[str, Any]:
    policy_path = data_root / "route-proof-policy.json"
    transition_path = data_root / "route-transitions.json"
    transition_evidence_path = data_root / "route-transition-evidence-v2.jsonl"
    evidence_path = data_root / "route-evidence-v2.jsonl"
    policy = route_evidence.load_policy(policy_path)
    transition_definitions = route_evidence.load_transition_definitions(transition_path)
    transition_evidence_rows = route_evidence.load_jsonl(transition_evidence_path)
    existing_evidence = route_evidence.load_jsonl(evidence_path)
    addon_data = repo_root / "ashita" / "addons" / "accessxi_reader" / "data"
    catalogue = route_evidence.load_route_catalogue_files(
        addon_data / "ffxi-nav-destinations.tsv",
        addon_data / "ffxi-nav-zoneline-graph.tsv",
    )
    candidates = route_inputs.get("candidates")
    if not isinstance(candidates, (list, tuple)):
        raise route_evidence.RouteEvidenceError(
            "Objective build did not supply typed Task 3 route candidates."
        )
    transition_registry_sha256 = hashlib.sha256(transition_path.read_bytes()).hexdigest()

    def execute(probe_executable: Path | None) -> dict[str, Any]:
        def probe_runner(
            _zone: int, requests: list[dict[str, Any]] | tuple[dict[str, Any], ...]
        ) -> tuple[dict[str, Any], ...]:
            if probe_executable is None:
                raise route_evidence.RouteEvidenceError(
                    "Route refresh requested a native probe without a published worker."
                )
            process = route_evidence.run_native_probe_worker(
                probe_executable,
                third_party_root=third_party_root,
                requests=requests,
                timeout_seconds=300.0,
            )
            return route_evidence.parse_probe_jsonl(
                requests, process.stdout, process.exit_code
            )

        return route_evidence.execute_compiled_route_pipeline(
            candidates=candidates,
            catalogue=catalogue,
            policy=policy,
            third_party_root=third_party_root,
            transition_registry_sha256=transition_registry_sha256,
            transition_definitions=transition_definitions,
            transition_evidence=transition_evidence_rows,
            existing_evidence=existing_evidence,
            refresh=refresh,
            offline=not refresh,
            probe_runner=probe_runner,
        )

    if refresh:
        with tempfile.TemporaryDirectory(prefix="accessxi-navprobe-") as temporary:
            executable = route_evidence.publish_navprobe(
                repo_root, Path(temporary) / "publish"
            )
            result = execute(executable)
    else:
        result = execute(None)
    evidence_payload = route_evidence.render_route_evidence_jsonl(
        (*result["accepted_evidence"], *result["review"])
    )
    _atomic_bytes(evidence_path, evidence_payload)
    generated = route_evidence.write_route_runtime_artifacts(
        repo_root=repo_root,
        third_party_root=third_party_root,
        policy=policy,
        contracts=result["contracts"],
        transitions=result["current_transitions"],
        runtime_ready=runtime_ready,
    )
    if update_runtime_pin_path is not None:
        route_evidence.update_runtime_pin(
            update_runtime_pin_path,
            generated["manifest_sha256"],
            marker="ACCESSXI_OBJECTIVE_ROUTE_MANIFEST_SHA256",
        )
    return {
        **generated,
        "accepted_evidence_count": len(result["accepted_evidence"]),
        "review_count": len(result["review"]),
        "unresolved_count": len(result["unresolved"]),
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Build AccessXI's offline, revisioned mission and quest guidance data."
    )
    parser.add_argument(
        "command", choices=("manifest", "fetch", "build", "routes", "report", "all")
    )
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument(
        "--ffxi-root",
        type=Path,
        default=Path(r"C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI"),
    )
    parser.add_argument("--cache-root", type=Path)
    parser.add_argument("--module-root", type=Path)
    parser.add_argument("--data-root", type=Path)
    parser.add_argument(
        "--third-party-root",
        type=Path,
        help="Explicit read-only root containing the pinned FFXINAV DLL and navmeshes.",
    )
    parser.add_argument(
        "--update-runtime-pin",
        type=Path,
        help="Update the single reviewed runtime manifest digest marker after generation.",
    )
    parser.add_argument(
        "--runtime-ready",
        action="store_true",
        help="Require the later runtime consumer child and emit only a complete runtime manifest.",
    )
    parser.add_argument(
        "--site",
        action="append",
        choices=tuple(SITE_CONFIG),
        dest="sites",
        help="Limit source acquisition to one site; repeat to select both.",
    )
    parser.add_argument("--offline", action="store_true", help="Refuse all source network access.")
    parser.add_argument(
        "--refresh",
        action="store_true",
        help="Fetch and atomically replace complete source snapshots.",
    )
    return parser


def _refresh_modes(
    *, command: str, refresh: bool, offline: bool
) -> tuple[bool, bool, bool]:
    route_refresh = command == "routes" and refresh
    source_refresh = command != "routes" and refresh
    source_offline = offline or command == "routes"
    return route_refresh, source_refresh, source_offline


def _route_dependency_root(repo_root: Path, selected: Path | None) -> Path:
    return route_evidence.validate_dependency_root(
        selected if selected is not None else repo_root / "third_party"
    )


def run(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    route_refresh, source_refresh, source_offline = _refresh_modes(
        command=args.command, refresh=args.refresh, offline=args.offline
    )
    repo_root = args.repo_root.resolve()
    cache_root = (args.cache_root or repo_root / "tools" / "objective_guides_cache").resolve()
    module_root = (
        args.module_root
        or repo_root / "ashita" / "addons" / "accessxi_reader" / "modules"
    ).resolve()
    data_root = (args.data_root or repo_root / "data" / "mission-quest-guides").resolve()

    if args.command == "report":
        _print_report(data_root)
        return 0

    native_rows = build_native_manifest(args.ffxi_root.resolve())
    _atomic_json(data_root / "native-manifest.json", _native_payload(native_rows))
    print(f"Decoded {len(native_rows)} valid native objectives.")
    if args.command == "manifest":
        return 0

    selected_sites = tuple(dict.fromkeys(args.sites or SITE_CONFIG))
    site_config_path = data_root / "source-site-config.json"
    if source_refresh:
        if args.offline:
            raise MediaWikiError(
                "--offline refuses network access and cannot be combined with --refresh."
            )
        write_site_config_artifact(
            site_config_path,
            _capture_source_site_config(cache_root),
        )
    site_policies = load_site_link_policies(site_config_path)
    source_pages, discovery = _source_pages(
        native_rows,
        cache_root=cache_root,
        offline=source_offline,
        refresh=source_refresh,
        sites=selected_sites,
    )
    print(f"Loaded {len(source_pages)} revisioned guide pages.")
    if args.command == "fetch":
        _atomic_json(data_root / "source-discovery.json", discovery)
        return 0

    parsed_pages, parse_failures = _parse_pages(
        source_pages,
        site_policies=site_policies,
    )
    overrides = _overrides_for_sites(
        _load_overrides(data_root / "reviewed-overrides.json"),
        selected_sites,
    )
    navigation_points, navigation_zone_names, navigation_edges = _load_navigation_catalog(
        repo_root / "data" / "ffxi-nav-destinations.tsv",
        repo_root / "data" / "ffxi-nav-zoneline-graph.tsv",
    )
    summary = build_guide_artifacts(
        native_rows,
        parsed_pages,
        module_root=module_root,
        data_root=data_root,
        reviewed_overrides=overrides,
        source_revisions=source_pages,
        parse_failures=parse_failures,
        navigation_points=navigation_points,
        navigation_zone_names=navigation_zone_names,
        navigation_edges=navigation_edges,
    )
    _atomic_json(data_root / "source-discovery.json", discovery)
    _atomic_json(
        data_root / "source-parse-failures.json",
        {"schema_version": 1, "failures": list(parse_failures)},
    )
    print(f"Parsed {len(parsed_pages)} objective pages; {len(parse_failures)} pages were excluded safely.")
    print(json.dumps(summary["counts"], sort_keys=True))
    if args.command in {"build", "routes", "all"}:
        route_summary = _build_route_artifacts(
            repo_root=repo_root,
            data_root=data_root,
            route_inputs=summary["route_inputs"],
            third_party_root=_route_dependency_root(repo_root, args.third_party_root),
            refresh=route_refresh,
            runtime_ready=args.runtime_ready,
            update_runtime_pin_path=(
                args.update_runtime_pin.resolve() if args.update_runtime_pin else None
            ),
        )
        print(
            "Objective route artifacts: "
            + json.dumps(route_summary, sort_keys=True)
        )
    if args.command in {"build", "routes", "all"}:
        _print_report(data_root)
    return 0


def main() -> None:
    try:
        raise SystemExit(run())
    except (MediaWikiError, route_evidence.RouteEvidenceError, OSError, ValueError) as error:
        print(f"objective guide build failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
