#!/usr/bin/env bash
# Runs every case study (schema.sql then solution.sql) and compares the query output with <case>/expected_output.txt.
# Usage: ./check.sh            verify (exit 1 on any difference)
#        ./check.sh --update   regenerate expected_output.txt (review the diff before committing)
# Needs psql and a server reachable through the usual PG* environment variables (database "postgres" must exist).
set -euo pipefail
update=${1:-}
fail=0
for d in */; do
  study=${d%/}
  [ -f "$study/schema.sql" ] || continue
  db=$(echo "$study" | tr - _)
  psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $db" -c "CREATE DATABASE $db"
  echo "== $study"
  psql -X -q -v ON_ERROR_STOP=1 -d "$db" -f "$study/schema.sql" > /dev/null
  out=$(mktemp)
  psql -X -q -v ON_ERROR_STOP=1 -P pager=off -d "$db" -f "$study/solution.sql" > "$out" 2> /dev/null
  if [ "$update" = "--update" ]; then
    cp "$out" "$study/expected_output.txt"; echo "   updated ($(wc -l < "$out") lines)"
  elif diff -u "$study/expected_output.txt" "$out" > /dev/null; then
    echo "   output matches expected_output.txt ($(wc -l < "$out") lines)"
  else
    echo "   MISMATCH in $study:"; diff -u "$study/expected_output.txt" "$out" | head -40; fail=1
  fi
  rm -f "$out"
done
exit $fail
