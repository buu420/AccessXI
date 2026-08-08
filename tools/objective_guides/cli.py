from __future__ import annotations

import argparse
import json
import sys
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
from .wikitext import WikitextError, parse_objective_page


SITE_CONFIG = {
    "bg": {
        "api_url": "https://www.bg-wiki.com/api.php",
        "categories": ("Category:Missions", "Category:Quests"),
    },
    "ffxiclopedia": {
        "api_url": "https://ffxiclopedia.fandom.com/api.php",
        "categories": ("Category:Missions", "Category:Quests"),
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
    return result


def _snapshot_path(cache_root: Path, site: str) -> Path:
    return cache_root / "snapshots" / f"{site}.json"


def _discover_and_fetch(
    client: MediaWikiClient,
    native_rows: tuple[NativeObjective, ...],
) -> tuple[tuple[PageRevision, ...], dict[str, Any]]:
    config = SITE_CONFIG[client.site]
    category_pages, categories = recursive_category_pages(client, config["categories"])
    category_titles = [page.title for page in category_pages]
    native_titles = [row.title for row in native_rows]
    requested_titles = tuple(dict.fromkeys((*category_titles, *native_titles)))
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


def _parse_pages(
    source_pages: tuple[PageRevision, ...],
) -> tuple[tuple[Any, ...], tuple[dict[str, Any], ...]]:
    parsed = []
    failures = []
    for page in sorted(source_pages, key=lambda value: (value.site, value.page_id)):
        try:
            parsed.append(parse_objective_page(page))
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


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Build AccessXI's offline, revisioned mission and quest guidance data."
    )
    parser.add_argument("command", choices=("manifest", "fetch", "build", "report", "all"))
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


def run(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
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
    source_pages, discovery = _source_pages(
        native_rows,
        cache_root=cache_root,
        offline=args.offline,
        refresh=args.refresh,
        sites=selected_sites,
    )
    print(f"Loaded {len(source_pages)} revisioned guide pages.")
    if args.command == "fetch":
        _atomic_json(data_root / "source-discovery.json", discovery)
        return 0

    parsed_pages, parse_failures = _parse_pages(source_pages)
    overrides = _overrides_for_sites(
        _load_overrides(data_root / "reviewed-overrides.json"),
        selected_sites,
    )
    summary = build_guide_artifacts(
        native_rows,
        parsed_pages,
        module_root=module_root,
        data_root=data_root,
        reviewed_overrides=overrides,
        source_revisions=source_pages,
        parse_failures=parse_failures,
    )
    _atomic_json(data_root / "source-discovery.json", discovery)
    _atomic_json(
        data_root / "source-parse-failures.json",
        {"schema_version": 1, "failures": list(parse_failures)},
    )
    print(f"Parsed {len(parsed_pages)} objective pages; {len(parse_failures)} pages were excluded safely.")
    print(json.dumps(summary["counts"], sort_keys=True))
    if args.command in {"build", "all"}:
        _print_report(data_root)
    return 0


def main() -> None:
    try:
        raise SystemExit(run())
    except (MediaWikiError, OSError, ValueError) as error:
        print(f"objective guide build failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
