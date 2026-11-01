---
name: ios-testflight-release
description: Archive, export, validate, upload, and verify this project's iOS build in TestFlight/App Store Connect. Use whenever the user asks to release, upload, archive, export, validate, or check processing for the ai-pose iOS app.
---

# iOS TestFlight Release

TestFlight distribution only. Do not submit to the public App Store, assign
testers, publish metadata, push, tag, create a release branch, or deploy the
backend. Do not alter production Firestore settings. Never print credentials,
API tokens, issuer values, or private-key contents.

## Current project facts

- Workspace: `mobile/iosApp/iosApp.xcworkspace`.
- Schemes: `Dev` and `Prod`. Production/TestFlight uses scheme `Prod`,
  configuration `Release-Prod` (`mobile/iosApp/Config/Prod-Release.xcconfig`).
  Never archive Dev for release.
- Bundle ID: `posing.camera.app`; team: `WZL67P53F2`.
- Marketing version is `CFBundleShortVersionString` in
  `mobile/iosApp/iosApp/Info.plist`; current source version is `1.1`.
  `CFBundleVersion` is also in that plist and is currently `14`; prior release
  used a temporary plist/override to ship build `4`. Discover the next unique
  build from App Store Connect before archiving; never assume the source build
  number equals the next available number.
- Latest accepted build: `1.1 (4)`, processing state `VALID`,
  `usesNonExemptEncryption=false`. The previous latest build was `1.0 (15)`;
  older notes claiming build 3 are stale. The `1.0` train is closed. For a new
  train, choose a marketing version greater than `1.1`; to add a build to an
  open train, use a new unique build number.
- Apple’s Paid Applications Agreement (PLA) must be accepted before export
  with cloud signing. If Apple reports an agreement error, stop until the
  agreement is accepted and the change has propagated.

## Before release

Confirm explicit user authorization, stable worktree, and that no mobile/QA
worker is using Xcode or the simulator. Do not use parallel release workers.
Do not reset, clean, checkout, or stash. Inspect and report pre-existing
changes; do not commit them. If a change can affect the archive, stop for
resolution.

Record baseline:

```bash
git rev-parse HEAD
git branch --show-current
git status --porcelain=v1
git diff --stat
git diff --check
```

Run the project’s full Dev test gate before archive:

```bash
scripts/ios-verify.sh
```

The script requires simulator `7CC9393C-88FC-4AE6-88D3-AC68A2E266B7`, uses
`/tmp/dd-shared`, and requires at least 1.5 GB free. Keep one `xcodebuild` at a
time. A test failure blocks release; report executed tests and failures. Also
check free disk before archiving and hold if below 2 GB.

Inspect the production Release configuration and report tester-visible
behavior before upload: `SERVER_BASE_URL` and `ServiceLocator` base URL, remote
feature-flag defaults, account/paywall state, purchase configuration (including
the `posing_pro` entitlement and the archived RevenueCat key shape), and
whether the four release-only debug launch arguments are absent. Do not change
production config or deploy server changes. Probe production routes only with
unauthenticated GET requests. Compare app calls with the deployed server and
call out routes or parameters that are missing; never mutate production.

## Discover build numbers and verify processing

Use the App Store Connect API to find builds, sorted by `-uploadedDate`, and
inspect `processingState` and `usesNonExemptEncryption`. Do not rely on stale
notes or guess a build number. API credentials are stored locally at
`~/.config/camerapose/asc-issuer-id` and
`~/.appstoreconnect/private_keys/AuthKey_S2MHQL347V.p8`. Key ID
`S2MHQL347V` has cloud-signing access; `79JD9TZQWM` does not. Read the issuer
from the file inline and never display it. Do not use `altool --list-providers`
as an API-key preflight; that command does not support API-key authentication.

The following read-only example creates a short-lived ES256 JWT and prints only
the requested build fields. Set `APP_ID`, `BUILD`, and `MARKETING` to the
numeric ASC app ID, build number, and marketing version. It requires Python's
`cryptography` package. It does not print or write the issuer, private key, or
JWT.

```bash
APP_ID='numeric-app-id' BUILD='4' MARKETING='1.1' python3 - <<'PY'
import base64, json, os, time, urllib.parse, urllib.request
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils

key_id = 'S2MHQL347V'
issuer = open(os.path.expanduser('~/.config/camerapose/asc-issuer-id')).read().strip()
key_path = os.path.expanduser(f'~/.appstoreconnect/private_keys/AuthKey_{key_id}.p8')
private_key = serialization.load_pem_private_key(open(key_path, 'rb').read(), password=None)
def b64(data): return base64.urlsafe_b64encode(data).rstrip(b'=').decode()
now = int(time.time())
header = b64(json.dumps({'alg':'ES256','kid':key_id,'typ':'JWT'}, separators=(',',':')).encode())
claims = b64(json.dumps({'iss':issuer,'iat':now,'exp':now+900,'aud':'appstoreconnect-v1'}, separators=(',',':')).encode())
message = f'{header}.{claims}'.encode()
der = private_key.sign(message, ec.ECDSA(hashes.SHA256()))
r, s = utils.decode_dss_signature(der)
token = f'{header}.{claims}.{b64(r.to_bytes(32,"big") + s.to_bytes(32,"big"))}'
query = urllib.parse.urlencode({
    'filter[app]': os.environ['APP_ID'],
    'filter[version]': os.environ['BUILD'],
    'filter[preReleaseVersion.version]': os.environ['MARKETING'],
    'sort': '-uploadedDate',
    'fields[builds]': 'version,processingState,usesNonExemptEncryption,uploadedDate',
    'limit': '50',
})
request = urllib.request.Request(
    'https://api.appstoreconnect.apple.com/v1/builds?' + query,
    headers={'Authorization': 'Bearer ' + token})
with urllib.request.urlopen(request, timeout=30) as response:
    payload = json.load(response)
print(json.dumps([{
    'id': b['id'], 'version': b['attributes'].get('version'),
    'processingState': b['attributes'].get('processingState'),
    'usesNonExemptEncryption': b['attributes'].get('usesNonExemptEncryption'),
    'uploadedDate': b['attributes'].get('uploadedDate'),
} for b in payload.get('data', [])], indent=2))
PY
```

Keep JWT lifetime at 20 minutes or less. For build-number discovery, omit the
version filters, request enough results, and sort by `-uploadedDate`.

`altool --validate-app` and `--build-status` may connect and then time out.
Treat that as inconclusive; do not loop or infer the state. Check the ASC API
query above (or App Store Connect) and report the state actually observed.

## Archive and export

Create a temporary work directory under `/tmp/aipose-release`. Use
`-derivedDataPath /tmp/dd-shared`; reuse resolved packages with
`-clonedSourcePackagesDirPath /tmp/dd-shared/SourcePackages` and
`-disableAutomaticPackageResolution` when needed. Keep temporary plist and
ExportOptions outside the repository. Preserve marketing version and set a
unique build via a temporary Info.plist or build override, then verify the
archive plist before export.

Copy `mobile/.env` into the worktree **before** archiving. It holds
`REVENUECAT_PUBLIC_SDK_KEY`, is gitignored, and is therefore absent from any
clean checkout — including `/tmp/rel-*` worktrees such as `/tmp/rel-1.1`;
`Release-Prod` fails the "RevenueCat key provenance (Release-Prod)" build phase
with `error: Release-Prod needs the RevenueCat App Store public SDK key (appl_…)`
when it is missing. Copy it in and rebuild rather than working around the phase.
`/tmp` is wiped on reboot, so the copy in the main checkout is the only one to
keep; a `/tmp` worktree's `.env` is disposable and must be deleted with it.

```bash
[ -f mobile/.env ] || { echo "STOP: mobile/.env missing in $(pwd)"; exit 1; }
# in a throwaway worktree: cp /path/to/main/checkout/mobile/.env mobile/.env
```

```bash
xcodebuild archive \
  -workspace mobile/iosApp/iosApp.xcworkspace \
  -scheme Prod \
  -configuration Release-Prod \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/dd-shared \
  -archivePath /tmp/aipose-release/iosApp-<marketing>-<build>.xcarchive \
  CURRENT_PROJECT_VERSION=<build>
```

If `CURRENT_PROJECT_VERSION` does not take effect, use a temporary copy of
Info.plist and `INFOPLIST_FILE=/tmp/aipose-release/Info.plist`. Do not edit
tracked files to set a release build number.

Before export, run both must-be-absent checks below against the archive. Stop if
any of them fails; do not work around a failure by editing the archive.

1. Debug launch arguments. These names are compiled out of Release by `#if DEBUG`
   (`AppConfig.swift`), and `AppConfigTests` proves it on the source — this check
   proves it on the shipped bytes. All **four** must be absent from the binary:
   `-AIPosePaywallEnabled`, `-AIPoseAccountsEnabled`, `-AIPosePurchasesConfigured`,
   `-AIPosePagingFixture`.
2. RevenueCat key provenance. The archived `Info.plist` `RevenueCatPublicSDKKey`
   value must not start with `test_`: a RevenueCat Test Store key is a fake store
   where purchases succeed and entitlements flip without money moving, and it is a
   `Debug-Dev`-only key (`mobile/iosApp/Config/Secrets.local.xcconfig`, included
   only by `Config/Dev-Debug.xcconfig`). The App Store value is not committed: it
   comes from the gitignored `mobile/.env`, which every `Config/*.xcconfig`
   includes — a build that could not read it never reached the archive, because
   the `Release-Prod` provenance phase fails first. Report whether the value is a
   placeholder (`REPLACE_WITH_…`/`$(…)`) — a placeholder archive ships
   unconfigured and is not a releasable purchase build.

The commands print verdicts only, never the archived key value:

```bash
ARCHIVE_APP=/tmp/aipose-release/iosApp-<marketing>-<build>.xcarchive/Products/Applications/posing.app

for arg in -AIPosePaywallEnabled -AIPoseAccountsEnabled -AIPosePurchasesConfigured -AIPosePagingFixture; do
  if strings -a "$ARCHIVE_APP/posing" | grep -qF -- "$arg"; then echo "STOP: $arg present in the Release binary"; fi
done

KEY_SHAPE="$(plutil -extract RevenueCatPublicSDKKey raw "$ARCHIVE_APP/Info.plist" \
  | sed -e 's/^test_.*/TEST_STORE_KEY/' -e 's/^appl_.*/app_store_key/' \
        -e 's/^REPLACE_WITH.*/PLACEHOLDER/' -e 's/^\$(.*/UNRESOLVED_SETTING/' \
        -e 't' -e 's/.*/other/'))"
echo "RevenueCatPublicSDKKey shape: $KEY_SHAPE"   # must be app_store_key
plutil -extract RevenueCatEntitlementID raw "$ARCHIVE_APP/Info.plist"   # must be posing_pro
```

A `TEST_STORE_KEY` or `UNRESOLVED_SETTING` shape is a stop. `PLACEHOLDER` means no
store on this build: record it in the report and treat the purchase matrix as
unverified rather than passed.

Use ExportOptions with method `app-store-connect`, team `WZL67P53F2`, automatic
signing, and `uploadSymbols=false` unless symbol upload is available. Export
with the API key that has cloud-signing access:

```bash
ISSUER="$(cat ~/.config/camerapose/asc-issuer-id)"
xcodebuild -exportArchive \
  -archivePath /tmp/aipose-release/iosApp-<marketing>-<build>.xcarchive \
  -exportPath /tmp/aipose-release/export \
  -exportOptionsPlist /tmp/aipose-release/ExportOptions.plist \
  -allowProvisioningUpdates \
  -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_S2MHQL347V.p8 \
  -authenticationKeyID S2MHQL347V \
  -authenticationKeyIssuerID "$ISSUER"
```

Do not echo or log `ISSUER`. PLA/agreement or cloud-signing errors block
export; resolve the stated prerequisite before another authorized attempt.
Inspect the IPA: bundle ID, marketing/build, Apple distribution signature,
App Store profile, `get-task-allow=false`, `beta-reports-active=true`, arm64,
dSYMs, and SHA-256. Keep the SHA-256 in the release report.

## Validate and upload once

After local inspection, run one bounded API-key validation (up to 120 seconds)
and upload exactly once (up to 300 seconds):

```bash
xcrun altool --validate-app -f /tmp/aipose-release/export/iosApp.ipa -t ios \
  --api-key S2MHQL347V --api-issuer "$ISSUER"
xcrun altool --upload-app -f /tmp/aipose-release/export/iosApp.ipa -t ios \
  --api-key S2MHQL347V --api-issuer "$ISSUER"
```

Capture the Delivery UUID. A timed-out upload is ambiguous: query its status
before any retry. Never retry a duplicate build rejection (`-19232` or
`-19241`) blindly. If ASC says the train is closed or requires a higher
marketing version, stop and report it. Do not switch keys or create signing
assets by another method without explicit authorization.

Use the ASC API query above as the authoritative processing check. If altool
status times out after connecting, do not retry repeatedly; report the timeout
and confirm through the API/App Store Connect. Report `VALID`, `PROCESSING`,
or other state only when observed.

After upload and status are verified, remove the archive and export under
`/tmp/aipose-release` if requested by the release task, while retaining the IPA
SHA-256. Check free disk afterward. Never delete unrelated simulator data;
when instructed, clean dead containers only for the approved simulator.

## Final report

Report commit, marketing/build, test count and failures, IPA SHA-256, key ID
only, Delivery UUID, validate/upload result, observed ASC processing state,
tester-visible defaults, the two archive checks (four debug arguments absent,
RevenueCat key shape), server compatibility gaps, scheme-diff verdict, and
free disk after cleanup. State any timeout or uncertainty plainly. Never
include credentials, issuer value, JWT, private-key contents, or the archived
RevenueCat key value.
