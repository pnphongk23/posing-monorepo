# Technical Design: iPhone Testing with Mobile MCP

## Objective and boundaries

Provide reproducible evidence that the iOS app builds, installs, launches, is
semantically operable, does not crash, and satisfies Camera scenarios on a real
iPhone. Mobile MCP owns interaction and evidence capture; Gradle/Xcode and
app-level assertions own compilation, signing, unit tests, files, and database
invariants.

Out of scope: Android, remote paid devices unless separately authorized, App
Store/TestFlight distribution, performance profiling, and replacing native unit
or integration tests with screenshot assertions.

## Selected architecture

```text
Harness scenario
  -> Gradle/Xcode build + signed artifact
  -> explicit physical iPhone + bundle ID
  -> Mobile MCP accessibility-first actions
  -> screenshots / recording / crash delta
  -> app-level file + database assertions
  -> evidence-backed Harness report
```

The workflow pins device ID, OS, bundle ID, app build/commit, Mobile MCP version,
and evidence paths. It refreshes the accessibility tree after each state change
and falls back to screenshot coordinates only when no semantic target exists.

## Why this design

- Mobile MCP has the required cross-cutting device tools but cannot prove an
  internal persistence transaction by itself.
- Real iPhone execution is mandatory for camera preview, captured bytes, flash,
  facing, zoom, and interruption behavior. Simulator evidence is useful only
  for layout/navigation/permission-state fixtures.
- A layered result prevents a visually plausible screenshot from being treated
  as proof of exactly one readable file and one matching metadata record.

## Environment contract

- Node.js 20+, Xcode command-line tools, an explicitly selected trusted iPhone.
- Active Mobile MCP server pinned to a recorded package version.
- Current iOS automation prerequisites verified by probe; official docs name
  go-ios, tunnel/forwarding, and WebDriverAgent, but upstream implementation has
  changed, so installed behavior is authoritative for setup diagnostics.
- A signed `.ipa` for physical-device installation, or an already installed
  development build whose exact identity is recorded.
- No silent daemon: tunnel, forwarding, WDA, or recording processes remain
  visible and are shut down deliberately after evidence collection.

## Scenario result contract

Each scenario records `Passed`, `Failed`, `Blocked`, or `Not tested`; device/OS;
app build; numbered actions; expected semantic/app state; evidence paths; crash
delta; cleanup; and limitations. Camera persistence claims additionally require
a readable file and matching database record, not only thumbnail change.

## Security and operations

- Installing/uninstalling and changing device state require the authorized test
  device. Never uninstall or reset a personal device implicitly.
- Remote cloud allocation is excluded unless the Maintainer explicitly accepts
  billing and destructive release semantics.
- Keep signing identities, UDIDs, and tokens out of committed reports; use
  redacted labels plus secure local configuration.
- Pin the Mobile MCP version for release evidence. Upgrade separately, inspect
  the live schema, and rerun the preflight.

## Known blockers

- Mobile MCP is absent from current Codex configuration.
- No real iPhone was online to `ios list` during planning.
- The existing shared iOS simulator test suite has a dependency compilation gap.

These blockers prevent runtime verification now; they do not justify weakening
the evidence contract.
