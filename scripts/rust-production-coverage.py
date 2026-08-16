#!/usr/bin/env python3
"""Production-only coverage report for the DevNav Rust workspace.

Consumes the JSON export produced by `cargo llvm-cov --json` (validated with
cargo-llvm-cov 0.8.7) and computes coverage over production code only, by
excluding exclusively items that are compiled solely under `#[cfg(test)]`:

- `#[cfg(test)] mod tests { ... }` modules (brace-matched);
- individual `#[cfg(test)]` helper functions/items.

Everything else, including uncovered host/terminal code, stays in the
denominator. Files instrumented by both the lib and the bin target (e.g.
config.rs) are deduplicated, as are generic instantiations of one function.

Metrics:
- regions: function regions with expanded-file-id 0 of production functions
  (matches llvm-cov's per-file region summary);
- lines: lines spanned by production function regions, covered when the
  innermost region executing them ran (matches llvm-cov line semantics);
- functions: production functions after dedup (reported, not gated).

Exit code is non-zero when the configurable thresholds are not met, and the
script fails closed (error exit) when the Rust source analysis is ambiguous
instead of silently excluding too much.

Usage:
    python scripts/rust-production-coverage.py coverage.json \
        [--threshold 80] [--regions-threshold N] [--json out.json]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

CRATE_RE = re.compile(r"Cs[0-9a-zA-Z]{11,13}_\d+dev(?:_nav)?")
GENERIC_MARKERS = ("ARe", "INt")


class SourceError(Exception):
    """Raised when Rust source analysis is ambiguous; the caller fails closed."""


def _strip_noncode(source: str) -> str:
    """Replace comments, strings, raw strings and char literals with spaces,
    preserving length and line structure, so brace matching never sees them."""
    out = list(source)
    i, n = 0, len(source)

    def blank(a: int, b: int) -> None:
        for k in range(a, b):
            if out[k] != "\n":
                out[k] = " "

    while i < n:
        c = source[i]
        if c == "/" and i + 1 < n and source[i + 1] == "/":
            j = source.find("\n", i)
            j = n if j < 0 else j
            blank(i, j)
            i = j
        elif c == "/" and i + 1 < n and source[i + 1] == "*":
            depth, j = 1, i + 2
            while j < n and depth:
                if source.startswith("/*", j):
                    depth += 1
                    j += 2
                elif source.startswith("*/", j):
                    depth -= 1
                    j += 2
                else:
                    j += 1
            if depth:
                raise SourceError("unterminated block comment")
            blank(i, j)
            i = j
        elif c == "r" and i + 1 < n and source[i + 1] in '"#':
            j = i + 1
            hashes = 0
            while j < n and source[j] == "#":
                hashes += 1
                j += 1
            if j < n and source[j] == '"':
                closer = '"' + "#" * hashes
                k = source.find(closer, j + 1)
                if k < 0:
                    raise SourceError("unterminated raw string")
                blank(i, k + len(closer))
                i = k + len(closer)
            else:
                i += 1
        elif c == '"':
            j = i + 1
            while j < n:
                if source[j] == "\\":
                    j += 2
                elif source[j] == '"':
                    break
                elif source[j] == "\n":
                    raise SourceError("unterminated string literal")
                else:
                    j += 1
            if j >= n:
                raise SourceError("unterminated string literal")
            blank(i, j + 1)
            i = j + 1
        elif c == "'":
            # char literal ('x', '\n', '{') vs lifetime ('a)
            m = re.match(r"'(\\.|[^\\'])'", source[i:])
            if m:
                blank(i, i + len(m.group(0)))
                i += len(m.group(0))
            else:
                i += 1
        else:
            i += 1
    return "".join(out)


CFG_TEST_RE = re.compile(r"#\s*\[\s*cfg\s*\(\s*test\s*\)\s*\]")


def find_test_ranges(path: str) -> list[tuple[int, int]]:
    """1-based inclusive (start, end) line ranges of #[cfg(test)] items."""
    try:
        source = Path(path).read_text(encoding="utf-8")
    except OSError as exc:
        raise SourceError(f"cannot read {path}: {exc}") from exc
    code = _strip_noncode(source)
    lines = code.splitlines()
    # map: does a line carry real code?
    ranges: list[tuple[int, int]] = []
    i, n = 0, len(lines)
    while i < n:
        if CFG_TEST_RE.search(lines[i]):
            j = i + 1
            # skip further attributes/comments between the attribute and item
            while j < n and (
                lines[j].strip().startswith("#") or not lines[j].strip()
            ):
                if not lines[j].strip() and not source.splitlines()[j].strip():
                    break
                j += 1
            k = j
            while k < n and "{" not in lines[k]:
                k += 1
            if k >= n:
                raise SourceError(
                    f"{path}: #[cfg(test)] at line {i + 1} has no braced item"
                )
            depth, end = 0, -1
            for m in range(k, n):
                depth += lines[m].count("{") - lines[m].count("}")
                if depth == 0:
                    end = m
                    break
            if end < 0:
                raise SourceError(
                    f"{path}: unbalanced braces for #[cfg(test)] item at line {i + 1}"
                )
            ranges.append((i + 1, end + 1))
            i = end + 1
        else:
            i += 1
    # sanity: braces of the whole file must balance
    whole = "\n".join(lines)
    if whole.count("{") != whole.count("}"):
        raise SourceError(f"{path}: unbalanced braces in file")
    return ranges


def _norm_name(name: str) -> str:
    """Normalize a mangled symbol: drop the crate disambiguator (lib dev_nav vs
    bin dev) and collapse generic instantiations of one function."""
    n = CRATE_RE.sub("@", name)
    cut = min((i for i in (n.find(m) for m in GENERIC_MARKERS) if i >= 0),
              default=len(n))
    return n[:cut]


def analyze(export: dict) -> dict:
    data = export["data"][0]
    per_file: dict[str, dict] = {}
    for fn in data["functions"]:
        regions0 = [r for r in fn["regions"] if r[5] == 0]
        if not regions0:
            continue
        fname = fn["filenames"][0]
        ls = min(r[0] for r in regions0)
        le = max(r[2] for r in regions0)
        key = (ls, le, _norm_name(fn["name"]))
        g = per_file.setdefault(fname, {})
        if key not in g:
            g[key] = {"count": 0, "regions": [list(r) for r in regions0]}
        cur = g[key]
        cur["count"] = max(cur["count"], fn["count"])
        if len(cur["regions"]) == len(regions0):
            for cr, nr in zip(cur["regions"], regions0):
                cr[4] = max(cr[4], nr[4])

    files_report = []
    totals = {"lines": [0, 0], "regions": [0, 0], "functions": [0, 0]}
    for fname in sorted(per_file):
        ranges = find_test_ranges(fname)
        prod = {
            k: v
            for k, v in per_file[fname].items()
            if not any(a <= k[0] <= b for a, b in ranges)
        }
        line_cov: dict[int, int] = {}
        for (ls, le, _n), info in prod.items():
            for r in info["regions"]:
                for line in range(r[0], r[2] + 1):
                    line_cov[line] = max(line_cov.get(line, 0), r[4])
        ln = len(line_cov)
        lc = sum(1 for v in line_cov.values() if v > 0)
        rn = sum(len(i["regions"]) for i in prod.values())
        rc = sum(1 for i in prod.values() for r in i["regions"] if r[4] > 0)
        fnn = len(prod)
        fc = sum(1 for i in prod.values() if i["count"] > 0)
        files_report.append(
            {
                "file": os.path.basename(fname),
                "lines": {"covered": lc, "count": ln},
                "regions": {"covered": rc, "count": rn},
                "functions": {"covered": fc, "count": fnn},
            }
        )
        totals["lines"][0] += lc
        totals["lines"][1] += ln
        totals["regions"][0] += rc
        totals["regions"][1] += rn
        totals["functions"][0] += fc
        totals["functions"][1] += fnn
    return {"files": files_report, "totals": totals}


def _pct(covered: int, count: int) -> float:
    return 100.0 * covered / count if count else 100.0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("export", help="cargo llvm-cov --json output file")
    ap.add_argument("--threshold", type=float, default=80.0,
                    help="minimum production line coverage percent")
    ap.add_argument("--regions-threshold", type=float, default=None,
                    help="minimum production region coverage percent "
                         "(defaults to --threshold)")
    ap.add_argument("--json", dest="json_out", default=None,
                    help="write machine-readable summary to this path")
    args = ap.parse_args(argv)
    regions_threshold = (
        args.threshold if args.regions_threshold is None else args.regions_threshold
    )

    try:
        with open(args.export, encoding="utf-8") as fh:
            export = json.load(fh)
        report = analyze(export)
    except (OSError, KeyError, json.JSONDecodeError) as exc:
        print(f"error: cannot analyze coverage export: {exc}", file=sys.stderr)
        return 2
    except SourceError as exc:
        print(f"error: ambiguous source analysis (failing closed): {exc}",
              file=sys.stderr)
        return 2

    for f in report["files"]:
        lp = _pct(f["lines"]["covered"], f["lines"]["count"])
        rp = _pct(f["regions"]["covered"], f["regions"]["count"])
        fp = _pct(f["functions"]["covered"], f["functions"]["count"])
        print(
            f"{f['file']:12s} lines {f['lines']['covered']}/{f['lines']['count']}"
            f" ({lp:.2f}%)  regions {f['regions']['covered']}/{f['regions']['count']}"
            f" ({rp:.2f}%)  functions {f['functions']['covered']}/{f['functions']['count']}"
            f" ({fp:.2f}%)"
        )
    t = report["totals"]
    lc, ln = t["lines"]
    rc, rn = t["regions"]
    fc, fnn = t["functions"]
    lp, rp, fp = _pct(lc, ln), _pct(rc, rn), _pct(fc, fnn)
    print(f"TOTAL lines {lc}/{ln} ({lp:.2f}%)  regions {rc}/{rn} ({rp:.2f}%)"
          f"  functions {fc}/{fnn} ({fp:.2f}%)")

    if args.json_out:
        summary = {
            "lines": {"covered": lc, "count": ln, "percent": round(lp, 4)},
            "regions": {"covered": rc, "count": rn, "percent": round(rp, 4)},
            "functions": {"covered": fc, "count": fnn, "percent": round(fp, 4)},
            "thresholds": {"lines": args.threshold, "regions": regions_threshold},
        }
        Path(args.json_out).write_text(
            json.dumps(summary, indent=2) + "\n", encoding="utf-8"
        )

    ok = True
    if lp < args.threshold:
        print(f"FAIL: production line coverage {lp:.2f}% < {args.threshold:.2f}%")
        ok = False
    if rp < regions_threshold:
        print(f"FAIL: production region coverage {rp:.2f}% < {regions_threshold:.2f}%")
        ok = False
    if ok:
        print(f"OK: production coverage meets thresholds "
              f"(lines >= {args.threshold:.2f}%, regions >= {regions_threshold:.2f}%)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
