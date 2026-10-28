# Paywall and purchase (FEAT-011)

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-PAY-001 | P0 | paywall switch on (launch arg), signed out | 1. Launch with the paywall on. 2. Open the camera. 3. Tap the shutter | Paywall sheet opens | pending: Dev build has no RevenueCat key so purchases stay unconfigured and the gate fails open (PremiumGate G3); needs a configured key or a debug purchases-configured switch |
| TC-PAY-002 | P0 | paywall switch off (launch arg) | 1. Launch with the paywall off. 2. Open the camera. 3. Tap the shutter | No paywall; camera stays on screen (simulator has no camera, so no photo is checked) | automated: TC-PAY-002-capture-ungated.yaml |
| TC-PAY-003 | P1 | paywall switch on, signed out | 1. Launch with the paywall on. 2. Open the camera. 3. Tap the shutter | Paywall shows the sign-in prompt | pending: Dev build has no RevenueCat key so purchases stay unconfigured and the gate fails open (PremiumGate G3); needs a configured key or a debug purchases-configured switch |
| TC-PAY-004 | P1 | Signed in, StoreKit test config | Pick plan, confirm test purchase | Entitled; capture succeeds | pending (queued E2E, after M01 closes) |
| TC-PAY-005 | P1 | Entitled | Sign out; capture | Paywall again | pending (queued E2E) |
| TC-PAY-006 | P1 | Sign in as different account | Capture | No entitlement carried over | pending (queued E2E) |
| TC-PAY-007 | P1 | Plans fail to load | Open paywall offline | "Retry loading Premium plans" works | manual |
| TC-PAY-008 | P1 | paywall switch on, signed out | 1. Launch with the paywall on. 2. Open the camera. 3. Tap the shutter. 4. Close the paywall | Camera visible again, paywall gone | pending: Dev build has no RevenueCat key so purchases stay unconfigured and the gate fails open (PremiumGate G3); needs a configured key or a debug purchases-configured switch |
