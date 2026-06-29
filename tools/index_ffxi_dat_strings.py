from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

from decode_ffxi_resources import DEFAULT_FFXI_ROOT, dat_files, parse_d_msg, parse_xistring


DEFAULT_XI_TINKERER = Path(r"C:\Users\buu42\AccessXI\tools\xi-tinkerer\xi-tinkerer-cli.exe")
DEFAULT_OUT_DIR = Path(r"C:\Users\buu42\AccessXI\pol_re\out\dat_index")
SCAN_RE = re.compile(r"^(?P<kind>\w+): DatId\((?P<dat_id>\d+)\) - (?P<path>.+\.DAT)$")


def relpath(path: Path, root: Path) -> str:
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def clean_text(text: str) -> str:
    return " ".join(text.replace("\r", "\n").split())


def run_scan(ffxi_root: Path, xi_tinkerer: Path) -> list[dict[str, str | int]]:
    if not xi_tinkerer.exists():
        raise FileNotFoundError(f"xi-tinkerer CLI not found: {xi_tinkerer}")
    result = subprocess.run(
        [str(xi_tinkerer), "scan-dats", str(ffxi_root)],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )

    rows: list[dict[str, str | int]] = []
    for line in result.stdout.splitlines():
        match = SCAN_RE.match(line.strip())
        if not match:
            continue
        path = Path(match.group("path"))
        rows.append(
            {
                "dat_id": int(match.group("dat_id")),
                "kind": match.group("kind"),
                "path": str(path),
                "relative_path": relpath(path, ffxi_root),
            }
        )
    return rows


def fallback_scan(ffxi_root: Path) -> list[dict[str, str | int]]:
    rows: list[dict[str, str | int]] = []
    for path in dat_files(ffxi_root):
        kind = ""
        if parse_xistring(path):
            kind = "XiStringTable"
        elif parse_d_msg(path):
            kind = "DmsgTable"
        if kind:
            rows.append(
                {
                    "dat_id": -1,
                    "kind": kind,
                    "path": str(path),
                    "relative_path": relpath(path, ffxi_root),
                }
            )
    return rows


def extract_rows(scan_rows: list[dict[str, str | int]]) -> list[dict[str, str | int]]:
    out: list[dict[str, str | int]] = []
    for dat in scan_rows:
        path = Path(str(dat["path"]))
        kind = str(dat["kind"])
        parsed: list[tuple[int, str]] = []
        parser = ""

        if kind == "XiStringTable":
            parsed = parse_xistring(path)
            parser = "parse_xistring"
        elif kind == "DmsgTable":
            parsed = parse_d_msg(path)
            parser = "parse_d_msg"

        for row, text in parsed:
            text = clean_text(text)
            if not text:
                continue
            out.append(
                {
                    "dat_id": int(dat["dat_id"]),
                    "dat_type": kind,
                    "dat_path": str(dat["relative_path"]),
                    "row": row,
                    "text": text,
                    "parser": parser,
                }
            )
    return out


def write_jsonl(path: Path, rows: list[dict[str, str | int]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")


def write_tsv(path: Path, rows: list[dict[str, str | int]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write("dat_id\tdat_type\tdat_path\trow\ttext\n")
        for row in rows:
            text = str(row["text"]).replace("\t", " ")
            handle.write(f"{row['dat_id']}\t{row['dat_type']}\t{row['dat_path']}\t{row['row']}\t{text}\n")


def read_jsonl(path: Path) -> list[dict[str, str | int]]:
    rows: list[dict[str, str | int]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def search_rows(rows: list[dict[str, str | int]], terms: list[str], limit: int) -> list[dict[str, str | int]]:
    lowered = [term.lower() for term in terms]
    hits = [
        row
        for row in rows
        if all(term in str(row["text"]).lower() for term in lowered)
    ]
    return hits[:limit]


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="Build and search a decoded FFXI DAT string index.")
    parser.add_argument("--root", type=Path, default=DEFAULT_FFXI_ROOT)
    parser.add_argument("--xi-tinkerer", type=Path, default=DEFAULT_XI_TINKERER)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument("--no-scan", action="store_true", help="Use the local decoder-only fallback scan.")
    parser.add_argument("--search", nargs="*", default=[], help="Search terms to match after building/loading.")
    parser.add_argument("--limit", type=int, default=80)
    parser.add_argument("--reuse", action="store_true", help="Reuse an existing JSONL index instead of rebuilding.")
    args = parser.parse_args()

    index_path = args.out_dir / "ffxi_dat_strings.jsonl"
    tsv_path = args.out_dir / "ffxi_dat_strings.tsv"
    scan_path = args.out_dir / "ffxi_dat_scan.jsonl"

    if args.reuse and index_path.exists():
        string_rows = read_jsonl(index_path)
        scan_rows: list[dict[str, str | int]] = []
    else:
        scan_rows = fallback_scan(args.root) if args.no_scan else run_scan(args.root, args.xi_tinkerer)
        string_rows = extract_rows(scan_rows)
        write_jsonl(scan_path, scan_rows)
        write_jsonl(index_path, string_rows)
        write_tsv(tsv_path, string_rows)

    print(f"FFXI root: {args.root}")
    if not (args.reuse and index_path.exists()):
        print(f"Scanned DATs: {len(scan_rows)}")
    print(f"Indexed strings: {len(string_rows)}")
    print(f"Index: {index_path}")
    print(f"TSV: {tsv_path}")
    print(f"Scan: {scan_path}")

    if args.search:
        hits = search_rows(string_rows, args.search, args.limit)
        print(f"\nSearch terms: {' | '.join(args.search)}")
        print(f"Hits: {len(hits)}")
        for hit in hits:
            print(
                f"{hit['dat_path']}#{hit['row']} "
                f"dat_id={hit['dat_id']} type={hit['dat_type']} text={hit['text']}"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
