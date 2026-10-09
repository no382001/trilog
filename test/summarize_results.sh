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

for f in "$DIR"/*_quad.xml "$DIR"/conformity.xml "$DIR"/api.xml; do
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

chart=$(printf '%s' "$rows" | awk -F'|' 'NF && $2 > 0 {
  name = $1; sub(/^test\/(quad|e2e)\//, "", name); sub(/_quad\.pl$/, "", name); sub(/\/\*\.bats$/, "", name); sub(/^\*\.bats$/, "e2e", name); sub(/^test\/conformity\/.*/, "conformity", name); sub(/^test\/api$/, "api", name)
  printf "%d|%s\n", int(100 * $3 / $2), name
}' | sort -t'|' -k1,1n -k2,2)

echo "### Test results"
echo ""
echo "$passed of $total tests pass, $failed fail, $crashed crash."
echo ""
if [ -n "$chart" ]; then
  echo '```mermaid'
  echo "xychart-beta horizontal"
  echo "  title \"Pass rate per file, %\""
  echo "  x-axis [$(printf '%s\n' "$chart" | cut -d'|' -f2 | sed 's/.*/"&"/' | paste -sd, -)]"
  echo "  y-axis \"pass %\" 0 --> 100"
  echo "  bar [$(printf '%s\n' "$chart" | cut -d'|' -f1 | paste -sd, -)]"
  echo '```'
  echo ""
fi
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
