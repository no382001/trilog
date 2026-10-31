#!/bin/bash
# Builds the PR comment from test-results-<name> directories, verdict first.
# usage: test/pr_report.sh results-dir...

failing=()
verdicts=""
for d in "$@"; do
  name="${d##*test-results-}"
  if [ -f "$d/verdict.md" ]; then
    v="$(cat "$d/verdict.md")"
  else
    v="- **$name**: no results, the tests did not run"
  fi
  [[ "$v" == *"no regressions"* ]] || failing+=("$name")
  verdicts+="$v"$'\n'
done

echo "<!-- trilog-tests -->"
if [ ${#failing[@]} -eq 0 ]; then
  echo "### Tests: no regressions"
else
  echo "### Tests: FAILED on ${failing[*]}"
fi
echo
printf '%s\n' "$verdicts"
echo "<details><summary>Charts and per-file results</summary>"
echo
for d in "$@"; do
  test/summarize_results.sh "$d" "${d##*test-results-}"
  echo
done
echo "</details>"
