#!/bin/bash
# Builds the markdown test-results table from JUnit XML output.
# Usage: test/summarize_results.sh [results-dir]
# Run directly (e.g. `make quad-junit && test/summarize_results.sh`) to
# debug the summary without going through CI.

set -euo pipefail

DIR="${1:-_build/test-results}"

rows=""
total=0; passed=0; failed=0; crashed=0
suite_count=0

for f in "$DIR"/*_quad.xml; do
  [ -f "$f" ] || continue
  suite_count=$((suite_count + 1))
  file=$(grep -oE 'file="[^"]*"' "$f" | head -1 | sed -E 's/file="(.*)"/\1/')
  [ -n "$file" ] || file="?"
  t=$(grep -oE 'tests="[0-9]+"' "$f" | grep -oE '[0-9]+' || echo 0)
  fl=$(grep -oE 'failures="[0-9]+"' "$f" | grep -oE '[0-9]+' || echo 0)
  p=$((t - fl))
  cr=$(grep -c '(trilog crashed here)' "$f" || true)
  rows="${rows}${file}|${t}|${p}|${fl}|${cr}"$'\n'
  total=$((total + t)); passed=$((passed + p)); failed=$((failed + fl)); crashed=$((crashed + cr))
done

if [ -f "$DIR/report.xml" ]; then
  st=$(grep -ohE 'tests="[0-9]+"' "$DIR/report.xml" | grep -oE '[0-9]+' | awk '{s+=$1} END{print s+0}')
  sf=$(grep -ohE 'failures="[0-9]+"' "$DIR/report.xml" | grep -oE '[0-9]+' | awk '{s+=$1} END{print s+0}')
  sp=$((st - sf))
  rows="${rows}test/e2e/*.bats|${st}|${sp}|${sf}|0"$'\n'
  total=$((total + st)); passed=$((passed + sp)); failed=$((failed + sf))
fi

failed_only=$((failed - crashed))
[ "$failed_only" -ge 0 ] || failed_only=0

echo "### Test results"
echo ""
echo '```mermaid'
echo "pie showData title $passed of $total tests pass"
echo "  \"Passed\" : $passed"
echo "  \"Failed\" : $failed_only"
echo "  \"Crashed\" : $crashed"
echo '```'
echo ""
echo "<details><summary>Per file</summary>"
echo ""
echo "| File | Tests | Passed | Failed | Crashed |"
echo "|---|---|---|---|---|"
printf '%s' "$rows" | sort -t'|' -k1,1 | awk -F'|' 'NF{print "| "$1" | "$2" | "$3" | "$4" | "$5" |"}'
echo "| **TOTAL** | **$total** | **$passed** | **$failed** | **$crashed** |"
echo ""
echo "</details>"

if [ "$suite_count" -eq 0 ]; then
  echo ""
  echo "**Warning:** no \`*_quad.xml\` files found in \`$DIR\` -- \`make quad-junit\` may not have run, or its output landed somewhere else."
fi
