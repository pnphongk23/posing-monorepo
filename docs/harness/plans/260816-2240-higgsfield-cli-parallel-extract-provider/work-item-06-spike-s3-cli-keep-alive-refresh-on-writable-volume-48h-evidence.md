---
work_item: 6
title: Spike S3 CLI keep-alive refresh on writable volume 48h evidence
status: blocked
priority: P2
effort: S
dependencies:
  - 5
decision_dependencies: []
status_reason: Requires 48h writable-volume spike evidence per design.md; S1 remains prod path; non-blocking for Cook completion
---

# Work Item 6: Spike S3 CLI keep-alive refresh on writable volume 48h evidence

**Kind:** verification (spike)

## Tasks

- Deploy staging Railway service with writable volume at
  `HIGGSFIELD_CREDENTIALS_PATH` (same layout as S1).
- Run periodic CLI commands (e.g. `higgsfield auth status`, lightweight
  `generate` dry-run if available) on interval (e.g. every 4h) for **≥48 hours**.
- Record whether CLI rewrites/refreshes `credentials.json` mtime and whether
  auth remains valid without human intervention.
- Compare file checksum/timestamp before and after each interval; log in evidence
  artifact `s3-spike-evidence.md`.
- If refresh does not persist >1 day, record **Failed** and confirm S1 remains
  production path (no architecture change).
- This Work Item is **non-blocking** for WI-7 functional tests except evidence
  attachment.

## Scope and affected files

- `docs/harness/plans/260816-2240-higgsfield-cli-parallel-extract-provider/s3-spike-evidence.md` (new)
- `web/services/pose-extract-server/scripts/higgsfield-credential-refresh-spike.sh` (new, optional)
- Railway staging volume config (documented)

## Success criteria

- 48h evidence log exists with timestamps, probe results, and credential file
  metadata.
- Conclusion stated: **S3 viable** (CLI refresh-writes persist) or **S3 not
  viable** (S1 only).
- No production dependency on S3 unless evidence is positive.
- Spike does not block merge of WI-1–5 if evidence incomplete; mark WI-6
  `pending` until 48h elapsed.

## Risks

- Staging credentials may expire independently of refresh behavior.
- 48h wall-clock delays Plan completion if treated as blocking; Plan marks this
  non-blocking per locked architecture item 9.
- Writable volume misconfiguration invalidates spike.

## Required evidence

- `s3-spike-evidence.md` with 48h timeline table (UTC timestamps).
- Redacted `credentials.json` stat output (`ls -la`, mtime) per checkpoint.
- Explicit recommendation: adopt S3 automation or retain S1-only runbook.
