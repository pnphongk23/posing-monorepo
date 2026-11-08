import XCTest

/// Architecture gate: a test may not mutate the *shared* session.
///
/// `ServiceLocator.sessionBoundary` and `ServiceLocator.tokenStorage` are the process-wide keychain
/// seam. A test that signs it out — or writes/clears credentials through it — does not stay in its
/// own test: `KeychainTokenStorage` is the real thing, so the simulator is left signed out for the app
/// and for every later test in the same run, and the damage surfaces as somebody else's red suite
/// (`APSavedListTests.testSignedOutShowsSignInGate` did exactly this).
///
/// Both branches are reachable without touching that seam: build a `SessionBoundary(tokenStorage:)`
/// over an in-memory `TokenStoring` and inject it (`SavedPosesScreen(model:boundary:)`,
/// `SessionPresenceModel(boundary:)`, `APSavedUndo(boundary:)`).
///
/// Limits, stated on purpose: this is text matching over the test target's sources. It cannot prove a
/// test does not reach the keychain some other way (a production type that owns the shared boundary and
/// exposes a mutation of its own), and a hit is a *mention* — a line that spells out the pattern in a
/// comment or a string counts too, which is why this file excludes itself rather than trying to strip
/// comments.
final class SessionMutationArchitectureTests: XCTestCase {
    /// Credential mutations on the shared seam. Reads (`loadCredentials`, `hasStoredSession`) are
    /// allowed: they cannot sign the simulator out.
    private static let forbidden = [
        "ServiceLocator.sessionBoundary.signOut(",
        "ServiceLocator.sessionBoundary.saveCredentials(",
        "ServiceLocator.sessionBoundary.clearForUnauthorized(",
        "ServiceLocator.tokenStorage.saveCredentials(",
        "ServiceLocator.tokenStorage.clearCredentials(",
    ]

    func testNoTestMutatesTheSharedSession() throws {
        let files = try testSourceFiles().filter { $0.standardizedFileURL != selfFile }
        XCTAssertFalse(files.isEmpty, "the scan found no test sources — the source path is wrong")

        var offenders: [String] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let lines = source.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                guard let hit = Self.forbidden.first(where: line.contains) else { continue }
                offenders.append("\(relativePath(of: file)):\(index + 1): \(hit)")
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            """
            these tests mutate the shared keychain session, which leaks into the app and every later \
            test on the simulator:
            \(offenders.joined(separator: "\n"))
            Inject a `SessionBoundary(tokenStorage:)` over an in-memory store instead.
            """
        )
    }

    // MARK: - Paths

    /// The file running the scan: its own `forbidden` array spells out every pattern.
    private var selfFile: URL {
        URL(fileURLWithPath: #filePath).standardizedFileURL
    }

    /// `…/mobile/iosApp/iosAppTests/Architecture/<this file>` → `…/mobile/iosApp/iosAppTests`.
    private var testSourceDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func relativePath(of file: URL) -> String {
        file.path.replacingOccurrences(of: testSourceDirectory.path + "/", with: "")
    }

    private func testSourceFiles() throws -> [URL] {
        let directory = testSourceDirectory
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: directory.path),
            "test sources not found at \(directory.path) — the scan cannot run"
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

