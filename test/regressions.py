#!/usr/bin/env python3
"""Compares a run's failing tests with test/known_failures.txt.

usage: test/regressions.py RESULTS_DIR [NAME]   prints a verdict, exits 1 on new failures
       test/regressions.py --update RESULTS_DIR  rewrites the baseline from a run
"""
import glob
import html
import os
import re
import sys

BASELINE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "known_failures.txt")
CASE = re.compile(r"<testcase\b([^>]*?)(/>|>(.*?)</testcase>)", re.S)
NAME = re.compile(r'\bname="([^"]*)"')


def results(d):
    failed, total, failures = set(), 0, 0
    for f in sorted(glob.glob(os.path.join(d, "*.xml"))):
        suite = os.path.basename(f)[: -len(".xml")]
        text = open(f, "rb").read().decode("utf-8", "replace")
        for m in CASE.finditer(text):
            name = NAME.search(m.group(1))
            if not name:
                continue
            total += 1
            body = m.group(3) or ""
            if "<failure" in body or "<error" in body:
                failures += 1
                failed.add(f"{suite}\t{html.unescape(name.group(1))}")
    return failed, total, failures


def main(args):
    if args[0] == "--update":
        failed, _, _ = results(args[1])
        with open(BASELINE, "w") as f:
            f.writelines(line + "\n" for line in sorted(failed))
        print(f"{len(failed)} known failures written to {BASELINE}")
        return 0
    name = args[1] if len(args) > 1 else os.path.basename(args[0])
    known = set(open(BASELINE).read().splitlines()) if os.path.exists(BASELINE) else set()
    failed, total, failures = results(args[0])
    new, fixed = sorted(failed - known), sorted(known - failed)
    passed = total - failures
    if new:
        print(f"- **{name}**: {len(new)} new failure(s), {passed}/{total} pass")
        for t in new[:20]:
            print(f"  - `{t.replace(chr(9), ' ► ')}`")
        if len(new) > 20:
            print(f"  - and {len(new) - 20} more")
    else:
        print(f"- **{name}**: no regressions, {passed}/{total} pass")
    if fixed:
        print(f"  - {len(fixed)} known failure(s) now pass; update the baseline with `make known-failures`")
    return 1 if new else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
