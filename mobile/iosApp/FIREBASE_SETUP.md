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
3. The same Firebase plist is intentionally used for both `Dev` and `Prod`;
   this lane does not split Firebase configuration files. No Xcode project
   change is required after regenerating from `project.yml` because the
   `iosApp` sources directory is included; otherwise add the file to the target
   manually.

## Xcode environment selection

Run the `Dev` or `Prod` scheme generated from `project.yml`. The selected
scheme resolves `AIPoseEnvironment` and `AIPoseBuildConfiguration` through the
matching `Config/*-*.xcconfig` file and exposes them to Kotlin via
`Info.plist`. Firebase remains best-effort and is not used as the environment
descriptor.

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
xcodebuild -list -workspace iosApp.xcworkspace
xcodebuild -workspace iosApp.xcworkspace -scheme Dev -sdk iphonesimulator -configuration Debug-Dev CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace iosApp.xcworkspace -scheme Prod -sdk iphonesimulator -configuration Release-Prod CODE_SIGNING_ALLOWED=NO build
```

Do not archive, upload to TestFlight, or repair keychains as part of this lane.
