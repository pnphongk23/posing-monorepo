# Prod-config simulator smoke (release 1.2) — flows and results

Release 1.2 (`release/1.2` = `ab5c9fc`), **Prod-config simulator build**, driven through flows that use
**no debug launch arguments**. A Release build compiles out every `-AIPose*` override
(`Core/Network/AppConfig.swift`: the whole `DebugLaunchArgumentOverride` reader sits inside `#if DEBUG`),
so what these flows exercise is the shipped path: behaviour comes from the Firestore `config/app`
document, not from a QA seam.

These files live outside `mobile/iosApp/maestro/` on purpose: `check-traceability.sh` requires every
file in `maestro/flows/` to be git-tracked *and* marked `automated:` in `docs/qa/test-cases/*.md`, and
that mapping is the main suite's, not this packet's. Promote a flow into `maestro/flows/` (and add its
case row) only if the release package decides it should stay.

## Prerequisites (each is a way a case becomes BLOCKED, never a way it "passes")

| Prerequisite | Needed by | If missing |
|---|---|---|
| Prod-config simulator build installed (`xcrun simctl install <UDID> <…/prod/posing.app>`) | all | nothing runs |
| Firestore `config/app.account_enabled == true` (already true) | S-02, S-04, S-05 (sign-in entry point) | BLOCKED-BY-FLAG — Settings has no Account row (`SupportScreens.swift:328`) |
| Firestore `config/app.extractPoseEnabled == true` | S-04 | BLOCKED-BY-FLAG — no Add pose entry (`APHomeHeader.showsAddPose`) |
| Firestore `config/app.paywall_enabled == true` | S-05 | BLOCKED-BY-FLAG — gate rule G1 allows capture |
| E2E account A (`E2E_EMAIL`/`E2E_PASSWORD`) signed in on the prod server | S-02, S-04, S-05 | BLOCKED — the flows `assertTrue` on the env before they touch the app |
| At least one photo in the simulator library | S-04 | the system picker has nothing to tap |

Credentials are never in this repo. They arrive only through
`set -a; . mobile/iosApp/maestro/e2e.local.env; set +a` in the running shell, then
`-e E2E_EMAIL="$E2E_EMAIL" -e E2E_PASSWORD="$E2E_PASSWORD"`. The App Review demo account
(`tester.posing.003`) is reserved and is not used by any flow here.

## Run (lane-2 simulator only, one flow at a time)

```bash
# bundle id of the Prod build, read from the artifact rather than assumed
APP_ID=$(plutil -extract CFBundleIdentifier raw /tmp/ai-pose-lane2-app-1.2/prod/posing.app/Info.plist)
set -a; . mobile/iosApp/maestro/e2e.local.env; set +a
[ -n "$E2E_PASSWORD" ] || { echo "credential file not filled"; exit 1; }
maestro --device "$UDID" test -e APP_ID="$APP_ID" \
  -e E2E_EMAIL="$E2E_EMAIL" -e E2E_PASSWORD="$E2E_PASSWORD" \
  docs/qa/prod-smoke/flows/S-01-launch-clean.yaml
```

Screenshots are written by the flows into `docs/qa/prod-smoke/screens/` (one per case, at the assertion
that proves the case).

## Cases

| Case | What the flow proves (business behaviour) | Flow |
|---|---|---|
| S-01 | A cold, clean launch on the shipping build reaches Home and renders a **real** pose card from the production catalogue — not an empty or error surface. | `flows/S-01-launch-clean.yaml` |
| S-02 | "Delete account" is a working entry point to the deletion request form: it leaves the app for `forms.gle/QJo1…` and does not touch the session (no self-delete, no in-app confirmation, the account is still signed in afterwards). Form never submitted. | `flows/S-02-delete-account-form.yaml` |
| ~~S-03~~ | N/A by design: the in-app Support & feedback row was removed on purpose in `54dda46`; the support form URL ships in App Store Connect only. Not a gap, not a blocker. | — |
| S-04 | The third-party-AI disclosure is shown *before* any photo leaves the device, Cancel sends nothing and records no answer, so the next submit asks again. No upload is performed (no AI cost, no job). | `flows/S-04-consent-sheet-prod.yaml` |
| S-05 | With `paywall_enabled` on, the paid action (shutter) opens the paywall for a signed-in, unentitled account, and closing it leaves the camera usable. No purchase is started. | `flows/S-05-paywall-gated-capture.yaml` |
| S-06 | Settings → About reports the binary the run happened on: `posing v1.2 (Build 16)`, read from the bundle. | `flows/S-06-about-version.yaml` |

## S-03 is N/A by design (not a gap)

`54dda46 chore(settings): remove support and feedback row` deletes the Settings row that opened
`SupportDestinations.support` on purpose: the support form URL is published in App Store Connect instead of
being an in-app entry point. That is why `SupportDestinations.support` still exists (pinned by
`SupportDestinationsTests`) while no view references it. There is no S-03 flow and no expected behaviour to
assert, so the case is dropped from this packet; it is not blocked and no UI change is requested.

## Results

Run: lane-2 `CF871F97`, Prod-config Release build `1.2 (16)` from `release/1.2` `ab5c9fc`,
`CFBundleIdentifier` `posing.camera.app` (read with `plutil` from the artifact). Every case ran on its own,
one at a time, with `maestro --device CF871F97-… test`. Firestore `config/app` was read *through the app*:
the Add pose header entry (extract switch) and the Settings Premium row (paywall switch) are rendered by
the same values the gates read, so their presence/absence is the flag state as the build sees it.
`account_enabled` was on; `extractPoseEnabled` was on; **`paywall_enabled` was off**.

| Case | Result | Evidence (screenshot) | Notes |
|---|---|---|---|
| S-01 | **PASS** | `screens/S-01-home-first-card.png` | clean launch with no launch arguments; Home rendered a real catalogue card (`poses.first-card`) from the production server, no error/empty surface |
| S-02 | **PASS** | `screens/S-02-delete-account-form.png` | signed in as the E2E account, Delete account opened Safari on the real "posing – Delete account request" form; returning to the app still showed the account signed in, so the row neither deletes nor drops the session. Form not submitted |
| ~~S-03~~ | N/A by design | — | removed in `54dda46`, no in-app entry point |
| S-04 | **PASS** | `screens/S-04-consent-sheet.png` | the sheet (`message` with the full disclosure, `allowButton`, `cancelButton`) appears on the first submit and again after Cancel; Cancel recorded no acknowledgement (the form stayed filled and no job was created). Nothing was uploaded: no AI cost, no job on the E2E account |
| S-05 | **BLOCKED-BY-FLAG** | `screens/S-05-paywall-flag-surface.png` | `paywall_enabled` is OFF: the shutter press correctly did nothing, and the flow stops at its own flag probe (the Settings Premium row, gated by the same value) rather than pretending to be a gate failure. Re-run once the switch is flipped |
| S-06 | **PASS** | `screens/S-06-about-version.png` | Settings → About reads `posing v1.2 (Build 16)`, i.e. the binary every other row above ran on |

No case reds. Four runs failed on **flow defects** before passing and are worth knowing for the next lane
(none of them is an app bug, and all are fixed in the committed files):

1. `hideKeyboard` before the sign-in CTA dismissed the keyboard by tapping, and the tap landed on the
   docked Sign in button — the sign-in actually succeeded, the next `tapOn: signin.submit` then failed
   because the sheet was already gone. The CTA sits outside the ScrollView (`SignIn.swift:537-566`), so
   the dismissal was never needed.
2. Asserting `forms.gle` in the Safari address field: `forms.gle/…` is a redirector, so the field shows
   `docs.google.com` and Safari chrome is outside Maestro's hierarchy anyway. The flow asserts the form's
   own title instead, which also proves the *right* destination loaded.
3. `inputText` for the tags field went into the pose name field: the tags field was under the keyboard,
   so the tap hit a key. Return now dismisses the keyboard between the two fields.
4. Maestro matches a `text` assertion against the element's **whole** accessibility text, so a partial
   phrase (the consent sentence, which also wraps over four lines) never matches; the assertion now uses
   `.*….*` with `\s+` between words, single-quoted so YAML keeps the backslashes.
