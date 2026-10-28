import XCTest

/// Architecture gate for the `SessionScoped` mechanism (ARCH-261029 P2).
///
/// The leaks this closes kept coming back because every model observed `SessionBoundary` by hand.
/// A behaviour test can only prove that *this* model resets; nothing stopped a new model from
/// holding Account data and forgetting the subscription. So the rule is checked against the source:
/// anything that declares `class`/`actor` and mentions an account token must either conform to
/// `SessionScoped` (and adopt itself into its `SessionScope`) or be listed in `exempt` with a reason.
///
/// Limits, stated on purpose: this is text matching. It misses Account data stored under a token
/// that is not in the list below, and it cannot tell whether a reset is *complete*. Completeness is
/// covered by one behaviour test per model (A loads → sign-out → B signs in → no A values).
final class SessionScopedArchitectureTests: XCTestCase {
    // MARK: - The rule

    /// Types that must be `SessionScoped`, with the Account state they hold.
    private static let scoped: [String: String] = [
        "PosesViewModel": "per-pose Saved state, in-flight bookmarks and the Saved/All list",
        "JobsService": "the Account's extraction jobs",
        "PaywallModel": "the Account's entitlement, plans and purchase phase",
        "AccountSessionModel": "the Account projection itself",
    ]

    /// Types that mention an account token but hold nothing the scope owns. Every entry needs a
    /// reason, and the reason has to name what keeps the data safe instead.
    private static let exempt: [String: String] = [
        "PoseCatalogCacheStore":
            "the epoch is checked inside the GRDB write transaction and SessionScopeCoordinator clears it",
        "RevenueCatAdapter":
            "owns the M01 identity epoch, which only SessionScopeCoordinator is allowed to move",
        "LiveRevenueCatSDK":
            "thin Purchases.shared seam; it stores no Account state, the adapter owns the identity",
        "SessionPresenceModel":
            "re-reads the boundary on every event, so it holds nothing to reset",
        "SessionScopeCoordinator":
            "is the app-scope orchestrator: it clears the catalog and the RevenueCat context",
    ]

    /// Account tokens: if a type mentions one of these it is holding Account-derived state.
    private static let accountTokens =
        #"\b(AccountSummary|savedOverrides|isSaved|PurchaseSnapshot|PurchaseProduct|entitlement|entitlements|JobRow|bookmark)\b"#

    func testEveryTypeThatMentionsAccountDataIsScopedOrExempt() throws {
        let declarations = try accountHoldingDeclarations()
        XCTAssertFalse(
            declarations.isEmpty,
            "the scan found no Account-holding declarations — the source path or the pattern is wrong"
        )

        var unregistered: [String] = []
        var notAdopted: [String] = []
        for declaration in declarations {
            if Self.scoped[declaration.name] != nil {
                // "scoped: its source contains `: …SessionScoped` and `scope.adopt(self)`".
                let conforms = declaration.source.contains("SessionScoped")
                let adopts = declaration.source.contains("adopt(self)")
                if !(conforms && adopts) {
                    notAdopted.append("\(declaration.name) (\(declaration.location))")
                }
                continue
            }
            if Self.exempt[declaration.name] != nil { continue }
            unregistered.append("\(declaration.name) (\(declaration.location))")
        }

        XCTAssertTrue(
            unregistered.isEmpty,
            """
            these types mention account data but are neither SessionScoped nor exempt:
            \(unregistered.joined(separator: "\n"))
            Either adopt a SessionScope (conform to SessionScoped + `scope.adopt(self)`) or add an \
            exempt entry with a reason to SessionScopedArchitectureTests.
            """
        )
        XCTAssertTrue(
            notAdopted.isEmpty,
            """
            listed as scoped but the mechanism is missing (needs `SessionScoped` and `adopt(self)`):
            \(notAdopted.joined(separator: "\n"))
            """
        )
    }

    func testExemptListExplainsEveryEntry() {
        XCTAssertTrue(
            Set(Self.scoped.keys).isDisjoint(with: Set(Self.exempt.keys)),
            "a type cannot be both scoped and exempt"
        )
        for (name, reason) in Self.exempt where reason.count < 20 {
            XCTFail("exempt entry \(name) needs a reason that says what keeps the data safe")
        }
        for (name, reason) in Self.scoped where reason.count < 20 {
            XCTFail("scoped entry \(name) needs a one-line reason naming the Account state it holds")
        }
    }

    // MARK: - Source scan

    private struct Declaration {
        let name: String
        let location: String
        /// From the declaration keyword through the end of its braced body.
        let source: String
    }

    private func accountHoldingDeclarations() throws -> [Declaration] {
        let tokenRegex = try NSRegularExpression(pattern: Self.accountTokens)
        var hits: [Declaration] = []
        for file in try appSourceFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            for type in try declaredTypes(in: source) {
                let range = NSRange(type.source.startIndex..., in: type.source)
                guard tokenRegex.firstMatch(in: type.source, range: range) != nil else { continue }
                let relative = file.path.replacingOccurrences(of: appSourceDirectory.path + "/", with: "")
                hits.append(Declaration(
                    name: type.name,
                    location: "\(relative): contains \(type.name)",
                    source: type.source
                ))
            }
        }
        return hits
    }

    private struct DeclaredType {
        let name: String
        let source: String
    }

    /// `class`/`actor` declarations at the start of a line (with visibility/final/attribute
    /// modifiers), each with its braced body.
    private func declaredTypes(in source: String) throws -> [DeclaredType] {
        let pattern =
            #"^[ \t]*(?:(?:public|private|internal|fileprivate|final|open|nonisolated|@[A-Za-z_]+)[ \t]+)*(?:class|actor)[ \t]+([A-Za-z_][A-Za-z0-9_]*)"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
        var result: [DeclaredType] = []
        for (index, match) in matches.enumerated() {
            guard let whole = Range(match.range, in: source),
                  let nameRange = Range(match.range(at: 1), in: source) else { continue }
            let declarationStart = whole.lowerBound
            let nextStart = index + 1 < matches.count
                ? Range(matches[index + 1].range, in: source)?.lowerBound
                : nil
            let limit = nextStart ?? source.endIndex
            guard let brace = source[whole.upperBound..<limit].firstIndex(of: "{") else { continue }
            let bodyEnd = balancedBodyEnd(in: source, openingBrace: brace, limit: source.endIndex)
            let end = max(bodyEnd, source.index(after: brace))
            result.append(DeclaredType(
                name: String(source[nameRange]),
                source: String(source[declarationStart..<end])
            ))
        }
        return result
    }

    /// Index just past the `}` that closes `openingBrace`, skipping comments and string literals so
    /// a brace inside a string cannot unbalance the scan. Falls back to the last index when the body
    /// never closes (a malformed or truncated snippet).
    private func balancedBodyEnd(in source: String, openingBrace: String.Index, limit: String.Index) -> String.Index {
        var depth = 0
        var index = openingBrace
        var inLineComment = false
        var inBlockComment = false
        var inString = false
        var escaped = false
        while index < limit {
            let character = source[index]
            let next = source.index(after: index)
            if inLineComment {
                if character == "\n" { inLineComment = false }
            } else if inBlockComment {
                if character == "*", next < limit, source[next] == "/" {
                    inBlockComment = false
                    index = next
                }
            } else if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else {
                switch character {
                case "/" where next < limit && source[next] == "/":
                    inLineComment = true
                    index = next
                case "/" where next < limit && source[next] == "*":
                    inBlockComment = true
                    index = next
                case "\"":
                    inString = true
                case "{":
                    depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 { return next }
                default:
                    break
                }
            }
            index = next
        }
        return limit
    }

    // MARK: - Paths

    private var appSourceDirectory: URL {
        // …/mobile/iosApp/iosAppTests/Architecture/<this file> → …/mobile/iosApp/iosApp
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("iosApp", isDirectory: true)
    }

    private func appSourceFiles() throws -> [URL] {
        let directory = appSourceDirectory
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: directory.path),
            "app sources not found at \(directory.path) — the scan cannot run"
        )
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }
}
