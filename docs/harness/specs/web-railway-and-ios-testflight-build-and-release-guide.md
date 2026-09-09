---
schema_version: 1
title: Web, Railway, and iOS TestFlight Build and Release Guide
relationships:
  specs: []
  decisions: []
  plans: []
  reports: []
  rules: []
  features: []
  source_paths: []
type: spec
status: draft
---

# Web, Railway, and iOS TestFlight Build and Release Guide

## Scope

This guide is the short release path for the web surfaces, the Railway-backed
pose service, and the iOS app. It describes commands and release gates; secrets,
signing credentials, and production values must remain in their respective
local/CI providers.

Related runbooks:

- [Railway deployment runbook](../../../web/services/pose-extract-server/DEPLOY_RUNBOOK.md)
- [iOS TestFlight release skill](../../../.agents/skills/ios-testflight-release/SKILL.md)

## Web build

Run from the repository root:

```bash
npm ci
npm run build
```

The root build delegates to `web/admin-ui` and runs the Next.js production
build. For the backend service, install and build independently when validating
the deployable service:

```bash
npm --prefix web/services/pose-extract-server ci
npm --prefix web/services/pose-extract-server run build
```

## Deploy the service to Railway

Deploy only from a clean, committed workspace, after the web/service checks
pass and the Railway project/service context is linked. From the repository
root—the directory containing `railway.toml`—run:

```bash
railway link
railway up
```

Use the [Railway deployment runbook](../../../web/services/pose-extract-server/DEPLOY_RUNBOOK.md)
for the project/service identifiers, required variables, deployment logs, and
post-deploy health checks. A release is not verified until the new deployment
is healthy and the documented smoke checks pass.

## Build and deliver iOS to TestFlight

Follow the repository's [`ios-testflight-release`](../../../.agents/skills/ios-testflight-release/SKILL.md)
skill as the authoritative procedure. In particular, complete its preflight,
signing/build, upload, and verification steps; do not treat a successful local
archive or upload as TestFlight availability until App Store Connect processing
and tester visibility are confirmed.

The minimum release evidence to record is:

- the selected Xcode scheme/configuration and version/build number;
- the archive/export or upload result;
- the App Store Connect processing state and the intended tester/group;
- any manual approval or release notes required by the skill.

## Release checklist

Before calling the release complete:

1. `npm ci` and `npm run build` pass from the repository root.
2. The backend service build passes.
3. `railway up` completes from the clean commit and the deployment health/smoke
   checks pass.
4. The iOS TestFlight skill's verification evidence is complete.
5. The commit, deployment identifier, and TestFlight build number are recorded
   together in the delivery report or release handoff.
