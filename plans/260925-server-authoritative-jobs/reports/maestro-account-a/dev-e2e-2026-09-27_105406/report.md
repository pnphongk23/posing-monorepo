# Phase 6 authenticated Dev E2E run

- Decision: STOPPED at the first post-submit assertion. The flow asserted the photo preview (`Change Photo`), exact name and tags, and an enabled submit button before issuing its single submit tap. The `Extracting Pose` processing state did not appear within 120 seconds.
- Candidate: `phase-06-account-a-authenticated-dev`; simulator `AIPose-Parity-iPhone13` (`4C1D6E55-2C31-4BD7-9881-F86F21CC53C8`); workspace `wks_2e69547344ec0a0b`.
- Job outcome: no job ID or accepted job status was observed; acceptance is unverified. The failure screenshot remains on the Add Pose form with the keyboard visible. No job list/detail/media phase was reached. No second attempt, navigation, reset, logout, or local API query was made.
- Preconditions: simulator was booted; Maestro hierarchy connected and showed the posing app; Dev health `/api/health` returned HTTP 200 before the run. Maestro syntax check returned `OK` for both the packet flow and this run copy.
- Deviation: the packet flow only checked submit visibility. The timestamped run copy adds `enabled: true` to that assertion to meet the packet acceptance condition. The read-only source flow is unchanged.
- Invocation: one `maestro test` invocation targeting only the named simulator; exit code 1. Raw output: `1/1 Flow Failed` at `Assertion is false: "Extracting Pose" is visible`.
- Evidence: `flow.yaml`, `raw-output.txt`, Maestro HTML report, debug output, pre-submit screenshot and failure artifacts are retained in this run directory. Credential-pattern scan found no matches in the seven text artifacts; screenshots were visually checked and show the form/photo without credentials.
- Next action: lead review of the failed post-submit transition and whether backend acceptance can be established from existing evidence. This worker did not retry or inspect Jobs.
