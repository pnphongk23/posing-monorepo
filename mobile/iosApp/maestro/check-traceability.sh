#!/usr/bin/env bash
# Fails if a flow is untracked, an automated case has no flow, a flow names an unknown case, or flow/case mapping is not 1:1.
set -euo pipefail
cd "$(dirname "$0")"
cases=../../../docs/qa/test-cases
rc=0
dup=$(grep -hoE '^\| TC-[A-Z]+-[0-9]+' $cases/*.md | tr -d '| ' | sort | uniq -d)
[ -z "$dup" ] || { echo "FAIL duplicate case IDs: $dup"; rc=1; }
auto=$(grep -hoE '^\| (TC-[A-Z]+-[0-9]+) \|.*\| automated: [^ |]+' $cases/*.md | sed -E 's/^\| (TC-[A-Z]+-[0-9]+) .*automated: ([^ |]+)/\1 \2/')
all=$(grep -hoE '^\| TC-[A-Z]+-[0-9]+' $cases/*.md | tr -d '| ')
for f in flows/*.yaml; do
  id=$(basename "$f" | grep -oE '^TC-[A-Z]+-[0-9]+')
  [ "$(ls flows | grep -c "^$id-" | tr -d ' ')" = 1 ] || { echo "FAIL $id: more than one flow"; rc=1; }
  head -1 "$f" | grep -qE "^# $id .+" || { echo "FAIL $f: first line must be '# $id <title>'"; rc=1; }
  echo "$all" | grep -qx "$id" || { echo "FAIL $f: unknown case $id"; rc=1; }
  grep -qE "^tags: \[$id(,|\])" "$f" || { echo "FAIL $f: tags must start with $id"; rc=1; }
  echo "$auto" | grep -qx "$id $(basename "$f")" || { echo "FAIL $f: case $id is not marked 'automated: $(basename "$f")'"; rc=1; }
done
while read -r id file; do
  [ -z "$id" ] && continue
  [ -f "flows/$file" ] || { echo "FAIL $id: flow flows/$file missing"; rc=1; }
done <<< "$auto"
# Every flow and subflow must be committed, or a clean checkout breaks the traceability table (QA_ALLOW_UNTRACKED=1 while drafting).
if [ -z "${QA_ALLOW_UNTRACKED:-}" ]; then
  for f in flows/*.yaml subflows/*.yaml; do
    git ls-files --error-unmatch "$f" >/dev/null 2>&1 || { echo "FAIL $f: not tracked by git"; rc=1; }
  done
fi
[ $rc -eq 0 ] && echo "traceability OK ($(ls flows | wc -l | tr -d ' ') flows)"
exit $rc
