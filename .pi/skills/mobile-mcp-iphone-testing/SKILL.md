---
name: mobile-mcp-iphone-testing
description: Configure, diagnose, and run reproducible iPhone simulator or real-device UI tests with mobile-next/mobile-mcp. Use for Mobile MCP device discovery, app install/launch, accessibility-first interaction, screenshots, recordings, crash evidence, Camera flows, and real-iPhone go-ios/WebDriverAgent/tunnel troubleshooting.
---

# Mobile MCP iPhone Testing

Use `@mobilenext/mobile-mcp` as an interaction and evidence layer. Keep build,
signing, unit tests, and storage/database assertions in the repository's native
toolchain; Mobile MCP does not replace them.

## Workflow

1. Read [setup.md](references/setup.md) when configuring or diagnosing the MCP,
   a simulator, or a real iPhone.
2. Read [tools-and-evidence.md](references/tools-and-evidence.md) before designing
   or executing a test flow.
3. Establish a clean baseline:
   - verify the native build and test commands;
   - call `mobile_list_available_devices` and select an explicit device ID;
   - record app bundle ID, build artifact path, OS version, and expected state;
   - stop if the requested real iPhone is offline or ambiguous.
4. Install only when the user authorized changing that device. Launch the app,
   then refresh `mobile_list_elements_on_screen` before each semantic action.
   Prefer accessibility bounds; use screenshot coordinates only as fallback.
5. For Camera tests, use a real iPhone for preview, capture, flash, facing, zoom,
   lifecycle interruption, and persistence claims. A simulator may validate
   layout, navigation, permission UI, and non-camera state only unless the app
   provides an explicit deterministic camera fixture.
6. Collect layered evidence:
   - native build/test output;
   - before/after accessibility snapshots;
   - screenshots at required visual checkpoints;
   - one screen recording for multi-step or timing-sensitive flows;
   - crash list/dump when a crash or termination occurs;
   - app-level storage/database evidence for persistence claims.
7. Report every scenario as **Passed**, **Failed**, **Blocked**, or **Not tested**.
   Include device, OS, app build, exact steps, evidence paths, and limitations.
   Never infer a camera or persistence pass from a screenshot alone.

## Safety and reliability

- Treat install, uninstall, launch, terminate, taps, input, orientation changes,
  and cloud-device allocation/release as device mutations.
- Do not allocate a billed remote device without explicit user authorization.
- Do not uninstall the app or reset device state unless the test requires it and
  the user authorized the data loss.
- Do not cache accessibility snapshots; the upstream tool contract explicitly
  requires refreshing them.
- Pin a known package version for repeatable CI or release evidence. Use
  `@latest` only for exploratory local setup, then record the resolved version.
- When upstream README, wiki, and installed behavior disagree, trust the
  installed tool schema and a reproducible probe; record the documentation gap.

## Output contract

Return a compact test report with environment, scenario matrix, evidence,
failures/blockers, and the smallest next action. State `Tôi không thể xác minh
điều này hoạt động vì...` when real-device prerequisites or observable evidence
are unavailable.
