---
work_item: 1
title: Establish real iPhone and Mobile MCP preflight
status: pending
priority: P1
effort: M
dependencies: []
decision_dependencies: []
---

# Work Item 1: Establish real iPhone and Mobile MCP preflight

**Kind:** technical

## Tasks

- Select one non-personal or explicitly authorized iPhone and record a redacted
  device label, OS version, and secure local UDID binding.
- Pin a verified `@mobilenext/mobile-mcp` version and register it in the active
  MCP client only after confirming the allowed global configuration change.
- Verify Node/Xcode, device trust, signing, `ios list`, current tunnel/forwarding
  requirement, automation runner health, and `mobile_list_available_devices`.
- Prove `mobile_list_apps` and `mobile_list_elements_on_screen` work on the chosen
  device; document diagnosis and shutdown steps without embedding secrets/UDID.
- Record upstream-version/schema evidence and any README/wiki/runtime mismatch.

## Scope and affected files

- `.agents/skills/mobile-mcp-iphone-testing/**` only if a verified correction is
  needed.
- A Plan-local or `docs/` runbook selected during Cook; no app behavior change.
- User-level MCP configuration is an external prerequisite, not a committed file.

## Success criteria

- One explicit real iPhone appears in Mobile MCP and returns a live accessibility
  tree.
- Mobile MCP version, client configuration, prerequisites, and cleanup commands
  are reproducible and contain no secret or raw device identifier in Git.
- A failed preflight stops before build installation or UI mutation and reports
  the smallest actionable cause.

## Risks

- Upstream iOS backend documentation may be stale relative to the installed
  release; validate with live tool calls.
- Installing/signing WebDriverAgent and opening a tunnel mutate the test device
  and host state; use only the authorized device and visible processes.

## Required evidence

- Redacted outputs for tool/package versions, Xcode device discovery, `ios list`,
  active tunnel/runner checks, MCP registration, device list, app list, and live
  element list.
- Exact source/version used for Mobile MCP tool schema.
