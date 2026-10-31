import XCTest
@testable import iosApp

@MainActor
final class AppleSignInTests: XCTestCase {
    func testSha256HexKnownVectorsAreLowercaseFixedWidthAndUnpadded() {
        XCTAssertEqual(
            AppleNonce.sha256Hex(""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        XCTAssertEqual(
            AppleNonce.sha256Hex("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertEqual(AppleNonce.sha256Hex("abc").count, 64)
        XCTAssertFalse(AppleNonce.sha256Hex("abc").contains("="))
        XCTAssertEqual(AppleNonce.sha256Hex("abc"), AppleNonce.sha256Hex("abc").lowercased())
    }

    func testRandomNonceHasMinimumLengthAndOnlyASCIIAlphanumerics() {
        let allowed = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".unicodeScalars)
        for _ in 0..<20 {
            let nonce = AppleNonce.random()
            XCTAssertGreaterThanOrEqual(nonce.count, 32)
            XCTAssertTrue(nonce.unicodeScalars.allSatisfy { allowed.contains($0) })
        }
    }

    func testActionSendsRawNonceToBackendAndHexNonceToAppleProvider() async throws {
        let provider = StubAppleAuthorizationProvider()
        var backendNonce: String?
        let action = AppleSignInAction(
            provider: provider,
            signIn: { _, nonce, _ in backendNonce = nonce }
        )

        let outcome = await action.run()
        XCTAssertEqual(outcome, .succeeded)
        let request = try XCTUnwrap(provider.requests.first)
        let rawNonce = try XCTUnwrap(backendNonce)
        XCTAssertEqual(request.rawNonce, rawNonce)
        XCTAssertEqual(request.requestNonce, AppleNonce.sha256Hex(rawNonce))
        XCTAssertNotEqual(request.requestNonce, rawNonce)
    }

    func testActionIncludesAndOmitsOptionalFullName() async {
        let namedProvider = StubAppleAuthorizationProvider(fullName: "Ada Lovelace")
        var named: String?
        let namedAction = AppleSignInAction(provider: namedProvider, signIn: { _, _, fullName in named = fullName })
        let namedOutcome = await namedAction.run()
        XCTAssertEqual(namedOutcome, .succeeded)
        XCTAssertEqual(named, "Ada Lovelace")

        let unnamedProvider = StubAppleAuthorizationProvider(fullName: nil)
        var unnamedWasCalled = false
        var unnamed: String? = "sentinel"
        let unnamedAction = AppleSignInAction(provider: unnamedProvider, signIn: { _, _, fullName in
            unnamedWasCalled = true
            unnamed = fullName
        })
        let unnamedOutcome = await unnamedAction.run()
        XCTAssertEqual(unnamedOutcome, .succeeded)
        XCTAssertTrue(unnamedWasCalled)
        XCTAssertNil(unnamed)
    }

    func testAppleSignInRequestOmitsNilFullName() throws {
        let data = try JSONEncoder().encode(AppleSignInRequest(
            identityToken: "identity-token",
            nonce: "raw-nonce",
            fullName: nil
        ))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertNil(json["fullName"])
    }

    func testCancellationIsCancelledWithoutErrorText() async {
        let provider = StubAppleAuthorizationProvider(error: CancellationError())
        let model = AppleSignInModel(action: AppleSignInAction(provider: provider, signIn: { _, _, _ in }))
        let succeeded = await model.signIn()
        XCTAssertFalse(succeeded)
        XCTAssertNil(model.error)
    }

    func testFailureUsesErrorCopyText() async {
        let provider = StubAppleAuthorizationProvider(error: AppleTestError.message)
        let model = AppleSignInModel(action: AppleSignInAction(provider: provider, signIn: { _, _, _ in }))
        let succeeded = await model.signIn()
        XCTAssertFalse(succeeded)
        XCTAssertEqual(model.error, "Apple sign-in failed.")
    }
}

private enum AppleTestError: Error, LocalizedError, Sendable {
    case message

    var errorDescription: String? { "Apple sign-in failed." }
}

@MainActor
private final class StubAppleAuthorizationProvider: AppleAuthorizationProviding {
    var requests: [AppleAuthorizationRequest] = []
    let fullName: String?
    let error: Error?

    init(fullName: String? = "Ada Lovelace", error: Error? = nil) {
        self.fullName = fullName
        self.error = error
    }

    func authorize(_ request: AppleAuthorizationRequest) async throws -> AppleAuthorizationResult {
        requests.append(request)
        if let error { throw error }
        return AppleAuthorizationResult(
            identityToken: "identity-token",
            rawNonce: request.rawNonce,
            fullName: fullName
        )
    }
}
