# Phase 6 authenticated Dev E2E — final — 2026-09-27 14:25 ICT

## Decisions

**PASS — one authenticated Dev extraction completed through pose detail.** At read-only preflight the existing session was signed in and Photos picker was open. The flow selected the visible top-left yoga image at `25%,25%`; the conditional sign-in branch was not needed. One pose was submitted after photo/name/tags/button assertions. No retry occurred.

## Candidate and results

- Pose name: `server-authoritative-jobs-e2e-final-20260927-1425`.
- Device: `AIPose-Parity-iPhone13`, UDID `4C1D6E55-2C31-4BD7-9881-F86F21CC53C8`.
- Dev admin/API health: HTTP 200/200. Syntax check: OK, exit 0.
- Maestro test invocations: **1**; exit status: **0**. `/tmp/phase6-auth-test.env` was removed after the run.
- Credential/email scan over sanitized text artifacts: **PASS**.

## Evidence

- `artifacts/screenshots/01-pre-submit-assertions-passed.png`: selected yoga image, unique title and tags, enabled Submit.
- `02-processing.png`: Processing Pose.
- `03-ready.png`: Pose Ready.
- `04-owner-scoped-job-ready.png`: Jobs screen with Finish selected and Ready rows; the flow asserted this exact candidate name, Ready status, and View pose.
- `05-pose-detail-media.png` plus `post-run-settled-detail.png`: detail title and rendered pose skeleton/media visible. The post-run read-only capture confirms the settled detail after the flow screenshot showed a transition.
- Job ID was not visible in approved UI evidence. UI status: Ready.
- Raw Maestro output, sanitized command trace/debug log, screenshots, HTML report, flow, preflight record and hashes are in this folder.

## Risks and next action

No unresolved acceptance blocker. The captured Jobs list truncates row titles visually; the exact unique title/status assertion passed in the flow. Hash validation and email scan are recorded in the manifest/check output.
