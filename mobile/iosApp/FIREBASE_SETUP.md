# Firebase setup runbook (FEAT-010 / DEC-007)

The Firebase iOS SDKs (Core, Analytics, Crashlytics, Remote Config) are wired
through the existing CocoaPods lane (`mobile/iosApp/Podfile`). The production
integration is a **native Swift Firebase bridge in `AppDelegate.swift`**; the
Kotlin side (`mobile/composeApp`) is a **pure contract/test seam only**
(`EndpointPolicy.validate`, `AppStartupConfig.resolveEndpointValue`,
`AppStartupConfig.applyEndpoint`). No Kotlin cinterop (`pod()`) is used: Kotlin
2.0.0 cannot parse the Xcode 26.1 SDK modulemap. Versions are pinned by
`mobile/iosApp/Podfile.lock`; do not upgrade unrelated dependencies.

## Supplying the real config (out of band, never committed)

1. Download `GoogleService-Info.plist` from the Firebase console for bundle id
   `camerapose.app`.
2. Copy it to `mobile/iosApp/iosApp/GoogleService-Info.plist`.
   - This exact path is git-ignored; the real file must never be committed.
   - `GoogleService-Info.plist.example` in this directory is a template with
     fake values only.
3. No Xcode project change is required for the resource if you regenerate the
   project via xcodegen (`project.yml` includes the `iosApp` sources dir);
   otherwise add the file to the `iosApp` target manually.

## Startup behavior

- On launch, `AppDelegate.swift` reads the plist from the app bundle and
  validates its shape (required keys present, `API_KEY` looks like a real key).
  Missing, malformed, or placeholder-shaped configs are skipped: the app boots
  without Firebase and Kotlin-side bridges report "unavailable" truthfully.
- When configured, Remote Config resolution happens once at startup before any
  API-backed state is created (see DEC-006). Analytics events and Crashlytics
  breadcrumbs are sanitized allowlists only.

## dSYM handling (Crashlytics)

- Crashlytics dSYM upload is a release build concern. Run the standard
  `"${PODS_ROOT}/FirebaseCrashlytics/upload-symbols" -gsp <GoogleService-Info.plist> -p ios <dSYMs>` step from CI or a local release archive.
- Upload failure must be treated as a diagnostic failure, never an app-launch
  failure. No dSYM upload runs during local verification.

## Verification gates

```
./gradlew :composeApp:allTests --console=plain
./gradlew :composeApp:compileKotlinIosSimulatorArm64 --console=plain
cd mobile/iosApp && pod install
xcodebuild -workspace iosApp.xcworkspace -scheme iosApp -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Do not archive, upload to TestFlight, or repair keychains as part of this lane.
