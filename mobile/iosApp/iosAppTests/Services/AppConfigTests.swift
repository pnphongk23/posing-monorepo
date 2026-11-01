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
            "-AIPosePagingFixture",
            "pagingFixtureFlag",
            "debugPagingFixtureOverride",
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

// MARK: - Release safety: a RevenueCat Test Store key must never ship (RC-CONFIG)

/// A RevenueCat **Test Store** key (`test_…`) is a fake store: a purchase succeeds and an
/// entitlement flips without money moving. Shipping one to TestFlight would hand premium capture to
/// anyone who taps Buy, so the Test Store key lives in the gitignored `Secrets.local.xcconfig`,
/// which only `Debug-Dev` includes — last, after the committed placeholder, so it wins.
///
/// The App Store key (`appl_…`) is not committed either: every configuration reads it from the
/// gitignored `mobile/.env`, included after the placeholder, so a clean checkout resolves the
/// placeholder (unconfigured, capture fail-open) while a release worktree copies `.env` in. A
/// `Release-Prod` build that still resolves a placeholder is failed by the project's
/// "RevenueCat key provenance" build phase, not by a test.
///
/// Limit, stated on purpose: this reads the four committed `.xcconfig` files and `Info.plist`. A
/// `REVENUECAT_PUBLIC_SDK_KEY=…` passed on the `xcodebuild` command line overrides all of it and is
/// invisible to any in-tree test, so `ios-testflight-release` repeats the check on the archived
/// plist before upload. The local file itself is never opened here: naming it is already the
/// finding, and its contents have no business in a test process.
final class RevenueCatConfigReleaseGuardTests: XCTestCase {
    private static let debugDev = "Dev-Debug.xcconfig"
    private static let configurations = [debugDev, "Dev-Release.xcconfig", "Prod-Debug.xcconfig", "Prod-Release.xcconfig"]
    private static let sdkKeySetting = "REVENUECAT_PUBLIC_SDK_KEY"
    private static let entitlementSetting = "REVENUECAT_ENTITLEMENT_ID"

    /// The whole point of the split: the file that may hold a fake store's key is reachable from
    /// exactly one configuration, and it is a Debug-Dev build — never a Release, never a PROD one.
    func testOnlyDebugDevReachesALocalSecretFile() throws {
        var offenders: [String] = []
        for configuration in Self.configurations where configuration != Self.debugDev {
            let locals = try Self.includeGraph(from: configuration).filter { $0.hasSuffix(".local.xcconfig") }
            offenders += locals.map { "\(configuration) → \($0)" }
        }

        XCTAssertEqual(
            offenders,
            [],
            "A local secret file may only be included by \(Self.debugDev); a Test Store key in any other configuration ships"
        )

        let debugDevGraph = try Self.includeGraph(from: Self.debugDev)
        XCTAssertTrue(
            debugDevGraph.contains("Secrets.local.xcconfig"),
            "\(Self.debugDev) must include the gitignored key file, otherwise no build can reach the store"
        )
    }

    /// xcconfig settings resolve top-down and the last assignment wins, so the optional Test Store
    /// include has to be the final line — above it, the committed placeholder or the `mobile/.env`
    /// App Store key would win over the Test Store key.
    func testDebugDevIncludesTheLocalFileAfterThePlaceholderItOverrides() throws {
        let lines = try Self.settingsLines(of: Self.debugDev)
        XCTAssertEqual(lines.last, "#include? \"Secrets.local.xcconfig\"")

        let keyLine = try XCTUnwrap(lines.firstIndex { $0.hasPrefix(Self.sdkKeySetting) })
        XCTAssertLessThan(keyLine, lines.count - 1, "the include must follow the placeholder it overrides")
    }

    /// Every configuration takes its real key from the same untracked `mobile/.env`, included after
    /// the committed placeholder so the env value wins. That is what makes the App Store key a
    /// one-line, one-place setup — and why a release worktree without `mobile/.env` archives an
    /// unconfigured build instead of failing silently.
    func testEveryConfigurationIncludesTheUntrackedEnvFileAfterItsPlaceholder() throws {
        let include = "#include? \"../../.env\""
        for configuration in Self.configurations {
            let lines = try Self.settingsLines(of: configuration)
            let envLine = try XCTUnwrap(
                lines.firstIndex(of: include),
                "\(configuration) must read mobile/.env, otherwise no build can reach the store"
            )
            let keyLine = try XCTUnwrap(lines.firstIndex { $0.hasPrefix(Self.sdkKeySetting) })
            XCTAssertLessThan(keyLine, envLine, "the include must follow the placeholder it overrides")
        }
    }

    /// The one file that is allowed to carry a real key is the untracked one the four committed
    /// configurations point at, and it is a template, not a key. It stays a valid xcconfig fragment
    /// — `//` comments only — so copying it to `mobile/.env` cannot break the build with a stray `#`.
    func testTheTrackedEnvFileIsATemplateNotAKey() throws {
        let template = try String(contentsOf: Self.envTemplate, encoding: .utf8)
        let values = template.split(separator: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("#"),
                  let separator = trimmed.firstIndex(of: "=") else { return nil }
            return String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
        }

        XCTAssertEqual(values.count, 1, "mobile/.env.example must define \(Self.sdkKeySetting) exactly once")
        XCTAssertFalse(
            AppConfigService.isValidRevenueCatKey(values.first),
            "the tracked template must never hold a usable key"
        )
    }

    /// Committed values only: the four files each carry a placeholder, and the `mobile/.env` they
    /// include is untracked, so no `test_…` key can be committed through them. The include itself
    /// is checked by `testEveryConfigurationIncludesTheUntrackedEnvFileAfterItsPlaceholder`.
    func testNoCommittedConfigurationCarriesATestStoreKey() throws {
        var offenders: [String] = []
        for configuration in Self.configurations {
            let values = try Self.values(of: Self.sdkKeySetting, in: configuration)
            XCTAssertEqual(values.count, 1, "\(configuration) must set \(Self.sdkKeySetting) exactly once")
            offenders += values
                .filter { $0.lowercased().hasPrefix("test_") }
                .map { _ in "\(configuration): \(Self.sdkKeySetting) starts with \"test_\"" }
        }

        XCTAssertEqual(offenders, [], "A RevenueCat Test Store key must never be committed")
    }

    /// …and the archived plist is those settings verbatim, which is what makes the claim above a
    /// claim about the shipped bundle rather than about a file nobody reads.
    func testTheInfoPlistTakesItsRevenueCatValuesFromTheBuildSettings() throws {
        let plist = try String(contentsOf: Self.infoPlist, encoding: .utf8)

        XCTAssertEqual(Self.plistString(for: "RevenueCatPublicSDKKey", in: plist), "$(\(Self.sdkKeySetting))")
        XCTAssertEqual(Self.plistString(for: "RevenueCatEntitlementID", in: plist), "$(\(Self.entitlementSetting))")
    }

    func testEveryConfigurationPinsTheDashboardEntitlementID() throws {
        for configuration in Self.configurations {
            let values = try Self.values(of: Self.entitlementSetting, in: configuration)
            XCTAssertEqual(values, ["posing_pro"], "\(configuration) must ship the entitlement id the dashboard grants")
        }

        XCTAssertTrue(
            AppConfigService.isValidIdentifier("posing_pro"),
            "an id the adapter filters out as a placeholder would leave every build unconfigured"
        )
    }

    /// The tree has to be green *without* the gitignored file: a fresh clone resolves `Debug-Dev` to
    /// the committed placeholder, the adapter refuses it, `isConfigured` stays `false`, and the
    /// capture gate fails open. Nothing in `ios-verify` may depend on a key that never ships.
    func testAPlaceholderKeyLeavesTheStoreUnconfiguredInsteadOfAssumingAccess() {
        XCTAssertFalse(AppConfigService.isValidRevenueCatKey("REPLACE_WITH_DEV_PUBLIC_SDK_KEY"))
        XCTAssertFalse(AppConfigService.isValidRevenueCatKey("$(\(Self.sdkKeySetting))"))
        XCTAssertTrue(AppConfigService.isValidRevenueCatKey("appl_ab12cd34ef56gh78"))
    }

    // MARK: - xcconfig reading

    /// Configuration names reachable through `#include` / `#include?`, as paths relative to
    /// `Config/`. A `*.local.xcconfig` is recorded but never opened, and an optional include of a
    /// file that is absent here (a fresh clone has no `mobile/.env`) is recorded without being
    /// opened either.
    private static func includeGraph(from configuration: String) throws -> [String] {
        var seen: Set<String> = []
        var pending = [configuration]
        while let next = pending.popLast() {
            guard seen.insert(next).inserted else { continue }
            guard !next.hasSuffix(".local.xcconfig"), let contents = try? text(of: next) else { continue }
            pending.append(contentsOf: includes(in: contents))
        }
        return seen.sorted()
    }

    /// The meaningful, non-comment lines of a configuration file, in file order.
    private static func settingsLines(of configuration: String) throws -> [String] {
        try text(of: configuration)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("//") }
    }

    private static func includes(in text: String) -> [String] {
        text.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#include"),
                  let open = trimmed.firstIndex(of: "\""),
                  let close = trimmed.lastIndex(of: "\""),
                  open < close else { return nil }
            return String(trimmed[trimmed.index(after: open)..<close])
        }
    }

    /// Every assignment of one setting in a single file, in file order (last one wins).
    private static func values(of setting: String, in configuration: String) throws -> [String] {
        try text(of: configuration).split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: "="),
                  trimmed[..<separator].trimmingCharacters(in: .whitespaces) == setting else { return nil }
            return trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        }
    }

    private static func plistString(for key: String, in plist: String) -> String? {
        guard let keyRange = plist.range(of: "<key>\(key)</key>") else { return nil }
        let tail = plist[keyRange.upperBound...].prefix(200)
        guard let open = tail.range(of: "<string>"), let close = tail.range(of: "</string>"),
              open.upperBound <= close.lowerBound else { return nil }
        return String(tail[open.upperBound..<close.lowerBound])
    }

    // MARK: - Paths

    private static var projectDirectory: URL {
        // …/iosAppTests/Services/<this file> → …/iosApp (the project directory holding Config/)
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var configDirectory: URL { projectDirectory.appendingPathComponent("Config", isDirectory: true) }
    private static var infoPlist: URL { projectDirectory.appendingPathComponent("iosApp/Info.plist") }
    /// `mobile/.env.example` — two levels above the project directory.
    private static var envTemplate: URL {
        projectDirectory.deletingLastPathComponent().appendingPathComponent(".env.example")
    }

    private static func text(of configuration: String) throws -> String {
        try String(contentsOf: configDirectory.appendingPathComponent(configuration), encoding: .utf8)
    }
}
