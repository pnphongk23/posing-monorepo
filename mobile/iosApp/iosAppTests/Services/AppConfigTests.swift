import XCTest
@testable import iosApp

final class AppConfigTests: XCTestCase {
    func testAccountFeatureFlagDefaultsToDisabled() {
        XCTAssertFalse(AppConfig().isAccountFeatureEnabled)
    }

    func testAccountFeatureFlagCanBeAppliedInBothDirections() {
        let config = AppConfig()

        config.applyAccountFeatureEnabled(false)
        XCTAssertFalse(config.isAccountFeatureEnabled)

        config.applyAccountFeatureEnabled(true)
        XCTAssertTrue(config.isAccountFeatureEnabled)
    }

    /// Extraction fails closed (D6 = A): a fresh install, a Firestore outage and a first paint
    /// before any payload all keep the Jobs/extraction surfaces hidden until an explicit `true`.
    func testExtractPoseFeatureFlagDefaultsToDisabled() {
        XCTAssertFalse(AppConfig().isExtractPoseEnabled)
        XCTAssertFalse(JobsEntryPolicy.canOpen(extractPoseEnabled: AppConfig().isExtractPoseEnabled))
    }

    func testExtractPoseFeatureFlagCanBeAppliedInBothDirections() {
        let config = AppConfig()

        config.applyExtractPoseEnabled(false)
        XCTAssertFalse(config.isExtractPoseEnabled)

        config.applyExtractPoseEnabled(true)
        XCTAssertTrue(config.isExtractPoseEnabled)
    }

    func testPaywallFeatureFlagDefaultsToDisabled() {
        XCTAssertFalse(AppConfig().isPaywallEnabled, "Fail-safe: a fresh config never gates capture")
    }

    func testPaywallFeatureFlagCanBeAppliedInBothDirections() {
        let config = AppConfig()

        config.applyPaywallEnabled(true)
        XCTAssertTrue(config.isPaywallEnabled)
        config.applyPaywallEnabled(false)
        XCTAssertFalse(config.isPaywallEnabled)
    }

    func testCanExtractPosePureFunction() {
        XCTAssertTrue(AppConfig.canExtractPose(isEnabled: true))
        XCTAssertFalse(AppConfig.canExtractPose(isEnabled: false))
    }

    func testJobsEntryIsBlockedWhenPoseExtractionIsDisabled() {
        XCTAssertFalse(JobsEntryPolicy.canOpen(extractPoseEnabled: false))
        XCTAssertTrue(JobsEntryPolicy.canOpen(extractPoseEnabled: true))
    }

    // MARK: - QA launch-argument overrides (`-AIPosePaywallEnabled`, `-AIPoseAccountsEnabled`)

    /// The reader is pure, so the Release answer is asserted from a Debug test run instead of a
    /// Release build: `isDebugBuild: false` is the only thing a shipping binary could produce.
    func testLaunchArgumentOverrideIsNilInReleaseBuilds() {
        let arguments = ["posing", "-AIPosePaywallEnabled", "YES", "-AIPoseAccountsEnabled", "YES"]

        XCTAssertNil(
            DebugLaunchArgumentOverride.booleanValue(
                for: "-AIPosePaywallEnabled",
                in: arguments,
                isDebugBuild: false
            ),
            "A Release build must never answer from argv"
        )
        XCTAssertNil(
            DebugLaunchArgumentOverride.booleanValue(
                for: "-AIPoseAccountsEnabled",
                in: arguments,
                isDebugBuild: false
            ),
            "A Release build must never answer from argv"
        )
    }

    func testLaunchArgumentOverrideAcceptsYesAndNoInBothSpellings() {
        func read(_ value: String) -> Bool? {
            DebugLaunchArgumentOverride.booleanValue(
                for: "-AIPosePaywallEnabled",
                in: ["posing", "-AIPosePaywallEnabled", value],
                isDebugBuild: true
            )
        }

        XCTAssertEqual(read("YES"), true)
        XCTAssertEqual(read("yes"), true)
        XCTAssertEqual(read("true"), true)
        XCTAssertEqual(read("NO"), false)
        XCTAssertEqual(read("no"), false)
        XCTAssertEqual(read("false"), false)
    }

    func testLaunchArgumentOverrideIsNilWithoutAFlagOrValue() {
        XCTAssertNil(
            DebugLaunchArgumentOverride.booleanValue(
                for: "-AIPosePaywallEnabled",
                in: ["posing"],
                isDebugBuild: true
            ),
            "No argument keeps the resolved payload in charge (fail closed)"
        )
        XCTAssertNil(
            DebugLaunchArgumentOverride.booleanValue(
                for: "-AIPosePaywallEnabled",
                in: ["posing", "-AIPosePaywallEnabled"],
                isDebugBuild: true
            ),
            "A flag with no value is not an override"
        )
        XCTAssertNil(
            DebugLaunchArgumentOverride.booleanValue(
                for: "-AIPosePaywallEnabled",
                in: ["posing", "YES", "-AIPosePaywallEnabled"],
                isDebugBuild: true
            ),
            "The value must follow its own flag"
        )
        XCTAssertNil(
            DebugLaunchArgumentOverride.booleanValue(
                for: "-AIPosePaywallEnabled",
                in: ["posing", "-AIPosePaywallEnabled", "garbage"],
                isDebugBuild: true
            ),
            "An unparsable value is not an override"
        )
    }

    #if DEBUG
    /// The Debug wiring is compiled in, and the harness spends no such argument: both switches and
    /// the payload defaults must read `false`, which is what a plain `xcodebuild test` launch sees.
    /// Guarded by `#if DEBUG` because a Release-configuration build has no such symbol to name —
    /// which is itself the property under test (`testLaunchArgumentOverrideIsNilInReleaseBuilds`).
    func testDebugWiringIsCompiledInAndSpendsNoArgumentHere() {
        XCTAssertNil(AppConfig.debugPaywallEnabledOverride)
        XCTAssertNil(AppConfig.debugAccountsEnabledOverride)
        XCTAssertFalse(AppConfig().isPaywallEnabled)
        XCTAssertFalse(AppConfig().isAccountFeatureEnabled)
    }
    #endif

    /// The reader above is always compiled (tests need it), so `#if DEBUG` around the *wiring* is
    /// the only thing keeping the argv lookup out of a shipping binary. Assert that here: the two
    /// argument names and every `ProcessInfo` argument lookup in `AppConfig.swift` must sit inside a
    /// `#if DEBUG` region.
    func testLaunchArgumentLookupIsCompiledUnderDebugOnly() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Services
                .deletingLastPathComponent() // iosAppTests
                .deletingLastPathComponent() // iosApp (project dir)
                .appendingPathComponent("iosApp/Core/Network/AppConfig.swift"),
            encoding: .utf8
        )

        let needles = [
            "ProcessInfo.processInfo.arguments",
            "-AIPosePaywallEnabled",
            "-AIPoseAccountsEnabled",
            "debugPaywallEnabledOverride",
            "debugAccountsEnabledOverride",
            "DebugLaunchArgumentOverride.paywallEnabledFlag",
            "DebugLaunchArgumentOverride.accountsEnabledFlag"
        ]
        var lines: [(number: Int, text: String, isDebug: Bool)] = []
        var stack: [(isDebug: Bool, inElse: Bool)] = []

        for (offset, rawLine) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#if") {
                stack.append((isDebug: line == "#if DEBUG", inElse: false))
                continue
            }
            if line.hasPrefix("#elseif") {
                continue
            }
            if line.hasPrefix("#else") {
                if !stack.isEmpty { stack[stack.count - 1].inElse = true }
                continue
            }
            if line.hasPrefix("#endif") {
                if !stack.isEmpty { stack.removeLast() }
                continue
            }
            let inDebug = stack.contains { $0.isDebug } && !stack.contains { $0.isDebug && $0.inElse }
            lines.append((offset + 1, line, inDebug))
        }

        let offenders = lines.filter { entry in
            needles.contains { entry.text.contains($0) } && !entry.isDebug
        }
        XCTAssertEqual(
            offenders.map { "\($0.number): \($0.text)" },
            [],
            "The launch-argument lookup and its flag names must be compiled only under #if DEBUG"
        )
        XCTAssertGreaterThan(
            lines.filter { $0.isDebug && $0.text.contains("ProcessInfo.processInfo.arguments") }.count,
            0,
            "The scan must actually see the DEBUG wiring it is guarding"
        )
    }
}
