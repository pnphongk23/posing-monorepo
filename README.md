# AI Pose

AI Pose is a monorepo for an iOS pose-reference camera, a local photo/pose library, an extraction API, and a small operational admin UI.

## Repository lanes

| Path | Purpose |
| --- | --- |
| `mobile/composeApp/` | Compose Multiplatform UI targeting iOS |
| `mobile/shared/` | SQLDelight persistence and Ktor API client |
| `mobile/iosApp/` | Native iOS host and camera integration |
| `web/admin-ui/` | Next.js admin UI and server-side API proxies |
| `web/services/pose-extract-server/` | Express extraction/community API and worker |
| `docs/harness/` | Current product, technical, feature, and UI/UX source of truth |
| `docs/superpowers/`, `plans/` | Historical designs and implementation plans |
| `docs/prototype/` | Interactive UI reference; not production behavior |

Start with the generated [Harness index](docs/harness/index.md), then read:

- [Technical architecture](docs/harness/specs/technical-architecture.md)
- [Product feature inventory](docs/harness/specs/product-feature-inventory.md)
- [UI/UX system](docs/harness/specs/ui-ux-system.md)

## Common checks

```sh
# Next.js admin
npm run lint
npm run build

# Express service
npm run backend:test
npm run backend:build

# iOS KMP modules
./gradlew :composeApp:compileKotlinIosSimulatorArm64 :shared:iosSimulatorArm64Test

# Documentation harness
ckh validate --all --workspace .
ckh index check --workspace .
ckh graph check --workspace .
```

## Local services

The root npm scripts route to the correct web workspace:

```sh
npm run dev          # Next.js admin UI
npm run backend:dev  # Express service
```

The Next.js server-side proxies require:

```env
POSE_EXTRACT_SERVER_URL=http://localhost:3001
POSE_EXTRACT_ADMIN_SECRET=change-me
```

The Express service has additional database, R2, provider, and worker configuration. Use `web/services/pose-extract-server/src/config/env.ts` as the executable configuration contract and never commit real secrets.

## Current limitations

- Mobile is iOS-only; no Android target is configured.
- The mobile Extract Pose action is not wired to a screen yet.
- Selecting “Use with Camera” returns to Camera but does not yet transfer the pose overlay.
- Public user-generated content must not launch until the gates in `docs/privacy-ugc-compliance.md` are implemented and verified.
- `sub2api/` is currently an untracked standalone checkout, not an integrated runtime lane.
