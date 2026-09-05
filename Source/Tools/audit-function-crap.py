#!/usr/bin/env python3
"""Audit changed functions using Lizard CC and optional LLVM LCOV line coverage.

Install the pinned parser with `python3 -m pip install lizard==1.24.0`.
Run from the repository root; absent coverage is conservatively zero.
"""

import argparse
from functools import partial, reduce
import json
from pathlib import Path
import re
import subprocess

import lizard


def git_output(arguments):
    return subprocess.check_output(["git", *arguments], text=True)


def supported_path(path):
    return Path(path).suffix in {".swift", ".mm", ".cpp", ".h", ".py"}


def changed_paths(base):
    tracked = git_output(["diff", "--name-only", base]).splitlines()
    untracked = git_output(["ls-files", "--others", "--exclude-standard"]).splitlines()
    return sorted(filter(supported_path, set(tracked + untracked)))


def changed_ranges(base, path):
    diff = git_output(["diff", "--unified=0", base, "--", path])
    matches = re.findall(r"^@@ -\d+(?:,\d+)? \+(\+?\d+)(?:,(\d+))? @@", diff, re.M)
    return tuple(map(hunk_range, matches))


def hunk_range(match):
    start, count = match
    return (int(start), int(start) + max(int(count or "1"), 1) - 1)


def intersects(function, line_range):
    return max(function.start_line, line_range[0]) <= min(function.end_line, line_range[1])


def function_changed(function, ranges):
    return not ranges or any(map(partial(intersects, function), ranges))


def normalized_source(path):
    source = Path(path).read_text()
    if Path(path).suffix == ".swift":
        # Lizard mistakes member calls named `set` for property accessors.
        return re.sub(r"(?<=\.)set(?=\s*\()", "storeValue", source)
    return source


def lcov_line(line):
    values = line.removeprefix("DA:").split(",")
    return (int(values[0]), int(values[1]))


def lcov_record(record):
    lines = record.strip().splitlines()
    source = next(filter(lambda line: line.startswith("SF:"), lines), "SF:")
    counts = dict(map(lcov_line, filter(lambda line: line.startswith("DA:"), lines)))
    return (str(Path(source.removeprefix("SF:")).resolve()), counts)


def read_coverage(path):
    if path is None:
        return {}
    return dict(map(lcov_record, Path(path).read_text().split("end_of_record")))


def counts_for_function(function, counts):
    return tuple(map(lambda item: item[1], filter(
        lambda item: function.start_line <= item[0] <= function.end_line, counts.items())))


def coverage_ratio(counts):
    if not counts:
        return 0.0
    return sum(map(lambda count: count > 0, counts)) / len(counts)


def function_row(path, coverage, function):
    counts = counts_for_function(function, coverage.get(str(Path(path).resolve()), {}))
    fraction = coverage_ratio(counts)
    complexity = function.cyclomatic_complexity
    return {
        "file": path, "function": function.long_name,
        "start_line": function.start_line, "end_line": function.end_line,
        "cyclomatic_complexity": complexity,
        "executable_lines": len(counts), "line_coverage": fraction,
        "crap": round(complexity ** 2 * (1 - fraction) ** 3 + complexity, 4),
        "conservative_zero_coverage": not counts,
    }


def analyze_path(base, coverage, path):
    functions = lizard.analyze_file.analyze_source_code(path, normalized_source(path)).function_list
    changed = filter(partial(function_changed, ranges=changed_ranges(base, path)), functions)
    return list(map(partial(function_row, path, coverage), changed))


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="HEAD")
    parser.add_argument("--lcov", help="LLVM `llvm-cov export -format=lcov` output")
    parser.add_argument("--max-crap", type=float, default=10)
    parser.add_argument("paths", nargs="*")
    return parser.parse_args()


def report(args):
    paths = args.paths or changed_paths(args.base)
    analyze = partial(analyze_path, args.base, read_coverage(args.lcov))
    rows = reduce(lambda result, items: result + items, map(analyze, paths), [])
    violations = list(filter(lambda row: row["crap"] > args.max_crap, rows))
    print(json.dumps({"formula": "CC^2 * (1 - line_coverage)^3 + CC",
                      "threshold": args.max_crap, "functions": rows,
                      "violations": len(violations)}, indent=2))
    return int(bool(violations))


if __name__ == "__main__":
    raise SystemExit(report(arguments()))
