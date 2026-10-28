#!/usr/bin/env bash
# Fails if an automated case has no flow, a flow names an unknown case, or flow/case mapping is not 1:1.
set -euo pipefail
cd "$(dirname "$0")"
cases=../../../docs/qa/test-cases
rc=0
auto=$(grep -hoE '^\| (TC-[A-Z]+-[0-9]+) \|.*\| automated: [^ |]+' $cases/*.md | sed -E 's/^\| (TC-[A-Z]+-[0-9]+) .*automated: ([^ |]+)/\1 \2/')
all=$(grep -hoE '^\| TC-[A-Z]+-[0-9]+' $cases/*.md | tr -d '| ')
for f in flows/*.yaml; do
  id=$(basename "$f" | grep -oE '^TC-[A-Z]+-[0-9]+')
  echo "$all" | grep -qx "$id" || { echo "FAIL $f: unknown case $id"; rc=1; }
  grep -qE "^tags: \[$id(,|\])" "$f" || { echo "FAIL $f: tags must start with $id"; rc=1; }
  echo "$auto" | grep -qx "$id $(basename "$f")" || { echo "FAIL $f: case $id is not marked 'automated: $(basename "$f")'"; rc=1; }
done
while read -r id file; do
  [ -z "$id" ] && continue
  [ -f "flows/$file" ] || { echo "FAIL $id: flow flows/$file missing"; rc=1; }
done <<< "$auto"
[ $rc -eq 0 ] && echo "traceability OK ($(ls flows | wc -l | tr -d ' ') flows)"
exit $rc
