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

    #if DEBUG
    /// The reader takes `isDebugBuild` as an input, so this pins the answer a Release build would
    /// give. Since the reader is itself compiled only under `#if DEBUG`, that answer exists as a
    /// runtime path only here — the compiled-out guarantee is `testLaunchArgumentLookupIsCompiledUnderDebugOnly`.
    func testLaunchArgumentOverrideIsNilInReleaseBuilds() {
        let arguments = ["posing", "-AIPosePaywallEnabled", "YES", "-AIPoseAccountsEnabled", "YES", "-AIPosePurchasesConfigured", "YES"]

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
        XCTAssertNil(
            DebugLaunchArgumentOverride.booleanValue(
                for: "-AIPosePurchasesConfigured",
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

    /// The Debug wiring is compiled in, and the harness spends no such argument: both switches and
    /// the payload defaults must read `false`, which is what a plain `xcodebuild test` launch sees.
    func testDebugWiringIsCompiledInAndSpendsNoArgumentHere() {
        XCTAssertNil(AppConfig.debugPaywallEnabledOverride)
        XCTAssertNil(AppConfig.debugAccountsEnabledOverride)
        XCTAssertNil(AppConfig.debugPurchasesConfiguredOverride)
        XCTAssertFalse(AppConfig().isPaywallEnabled)
        XCTAssertFalse(AppConfig().isAccountFeatureEnabled)
    }
    #endif

    /// `#if DEBUG` is the only thing keeping the argv lookup out of a shipping binary, so assert it
    /// on the source: every argument name, every DEBUG-only symbol and every `ProcessInfo` argument
    /// lookup in `AppConfig.swift` must sit in the primary branch of a `#if DEBUG` block.
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
            "-AIPosePurchasesConfigured",
            "DebugLaunchArgumentOverride",
            "paywallEnabledFlag",
            "accountsEnabledFlag",
            "purchasesConfiguredFlag",
            "debugPaywallEnabledOverride",
            "debugAccountsEnabledOverride",
            "debugPurchasesConfiguredOverride"
        ]
        let scanned = ConditionalCompilationScanner.scan(source)
        let offenders = scanned
            .filter { line in !line.isDebugOnly && needles.contains { line.text.contains($0) } }
            .map { "\($0.number): \($0.text)" }

        XCTAssertEqual(
            offenders,
            [],
            "The launch-argument lookup, its flag names and the reader must be compiled only under #if DEBUG"
        )
        XCTAssertGreaterThan(
            scanned.filter { $0.isDebugOnly && $0.text.contains("ProcessInfo.processInfo.arguments") }.count,
            0,
            "The scan must actually see the DEBUG wiring it is guarding"
        )
    }

    /// A lookup that escapes Release through the `#else` of an `#if DEBUG` block is the exact
    /// mistake the scan must catch. Proven on an in-memory source, so the scanner's branch tracking
    /// is tested instead of merely trusted.
    func testScannerFlagsAProcessInfoLookupInAnElseBranchOfADebugBlock() {
        let leaked = "let leaked = ProcessInfo.processInfo.arguments"
        let escaping = """
        #if DEBUG
        let compiledIn = 1
        #else
        \(leaked)
        #endif
        let live = ProcessInfo.processInfo.arguments
        """
        let protected = """
        #if DEBUG
        \(leaked)
        #endif
        """

        XCTAssertEqual(
            lookupsOutsideDebugOnlyBlocks(in: escaping),
            ["4: \(leaked)", "6: let live = ProcessInfo.processInfo.arguments"],
            "Both the #else branch and the code after #endif are compiled into Release"
        )
        XCTAssertEqual(lookupsOutsideDebugOnlyBlocks(in: protected), [])
    }

    /// Same for `#elseif`: the alternative branch of an `#if DEBUG` block is not the DEBUG branch,
    /// whatever its condition says — the guard errs toward a red test rather than toward a silent
    /// Release leak.
    func testScannerFlagsAProcessInfoLookupInAnElseIfBranchOfADebugBlock() {
        let leaked = "let leaked = ProcessInfo.processInfo.arguments"
        let negated = """
        #if DEBUG
        let compiledIn = 1
        #elseif !DEBUG
        \(leaked)
        #endif
        """
        let debugElseIf = """
        #if DEBUG
        let compiledIn = 1
        #elseif DEBUG
        \(leaked)
        #endif
        """

        XCTAssertEqual(lookupsOutsideDebugOnlyBlocks(in: negated), ["4: \(leaked)"])
        XCTAssertEqual(
            lookupsOutsideDebugOnlyBlocks(in: debugElseIf),
            ["4: \(leaked)"],
            "An #elseif branch is never treated as the guarded branch of its #if"
        )
    }

    /// The `-AIPosePurchasesConfigured` lookup is guarded by the same scan as the older switches, and
    /// the flag *name* counts as a leak on its own — a Release build must not even contain it.
    func testScannerGuardsThePurchasesConfiguredOverrideInAlternativeBranches() {
        let flagName = "\"-AIPosePurchasesConfigured\""
        let leakedElse = """
        #if DEBUG
        let compiledIn = 1
        #else
        let flag = \(flagName)
        #endif
        """
        let leakedElseIf = """
        #if DEBUG
        let compiledIn = 1
        #elseif !DEBUG
        let flag = \(flagName)
        #endif
        """
        let guarded = """
        #if DEBUG
        let flag = \(flagName)
        let override = DebugLaunchArgumentOverride.booleanValue(for: flag, in: [], isDebugBuild: true)
        #endif
        """

        XCTAssertEqual(flagsOutsideDebugOnlyBlocks(in: leakedElse, flag: "AIPosePurchasesConfigured"), ["4: let flag = \"-AIPosePurchasesConfigured\""])
        XCTAssertEqual(flagsOutsideDebugOnlyBlocks(in: leakedElseIf, flag: "AIPosePurchasesConfigured"), ["4: let flag = \"-AIPosePurchasesConfigured\""])
        XCTAssertEqual(flagsOutsideDebugOnlyBlocks(in: guarded, flag: "AIPosePurchasesConfigured"), [])
    }
}

/// Conditional-compilation scan for the `#if DEBUG` guards in the app sources.
///
/// A line is Debug-only when it sits in the **primary** branch of an enclosing `#if DEBUG` and no
/// enclosing `#if DEBUG` has moved to an alternative branch (`#else` / `#elseif`). Alternative
/// branches are treated as live code on purpose: `#elseif DEBUG` genuinely is Release-safe, but a
/// guard that errs toward a red test is worth more than one that could miss a real leak.
private enum ConditionalCompilationScanner {
    struct Line: Equatable {
        let number: Int
        let text: String
        let isDebugOnly: Bool
    }

    private struct Frame {
        let isDebug: Bool
        var isPrimaryBranch: Bool
    }

    static func scan(_ source: String) -> [Line] {
        var lines: [Line] = []
        var stack: [Frame] = []

        for (offset, rawLine) in source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated() {
            let text = rawLine.trimmingCharacters(in: .whitespaces)

            if text.hasPrefix("#if") {
                let isDebug = text == "#if DEBUG"
                stack.append(Frame(isDebug: isDebug, isPrimaryBranch: isDebug))
                continue
            }
            if text.hasPrefix("#elseif") || text.hasPrefix("#else") {
                if !stack.isEmpty { stack[stack.count - 1].isPrimaryBranch = false }
                continue
            }
            if text.hasPrefix("#endif") {
                if !stack.isEmpty { stack.removeLast() }
                continue
            }

            let isDebugOnly = stack.contains { $0.isDebug && $0.isPrimaryBranch }
                && !stack.contains { $0.isDebug && !$0.isPrimaryBranch }
            lines.append(Line(number: offset + 1, text: text, isDebugOnly: isDebugOnly))
        }

        return lines
    }
}

/// `ProcessInfo` argv lookups that a Release build would still compile in.
private func lookupsOutsideDebugOnlyBlocks(in source: String) -> [String] {
    ConditionalCompilationScanner.scan(source)
        .filter { !$0.isDebugOnly && $0.text.contains("ProcessInfo.processInfo.arguments") }
        .map { "\($0.number): \($0.text)" }
}

/// Any mention of a DEBUG-only launch-argument name that a Release build would still compile in.
private func flagsOutsideDebugOnlyBlocks(in source: String, flag: String) -> [String] {
    ConditionalCompilationScanner.scan(source)
        .filter { !$0.isDebugOnly && $0.text.contains(flag) }
        .map { "\($0.number): \($0.text)" }
}
