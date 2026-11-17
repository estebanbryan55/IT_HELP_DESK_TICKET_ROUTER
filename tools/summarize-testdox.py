"""Shortens `php artisan test --testdox` output to one line per test plus the
first line of each failure, so before/after runs can be compared side by side.

    python tools/summarize-testdox.py raw.txt summary.txt
"""
import sys

PASS, FAIL = "✔", "✘"

lines = open(sys.argv[1], encoding="utf8").read().splitlines()
out = []
for i, line in enumerate(lines):
    s = line.strip()
    if s.startswith(PASS):
        out.append("  " + s)
    elif s.startswith(FAIL):
        out.append("  " + s)
        nxt = lines[i + 1].strip() if i + 1 < len(lines) else ""
        out.append("      -> " + nxt[:220])
    elif "(Tests" in s and s.endswith(")"):
        out.append("\n" + s)
    elif s.startswith("Tests:"):
        out.append("\n" + s)
open(sys.argv[2], "w", encoding="utf8").write("\n".join(out).lstrip() + "\n")
