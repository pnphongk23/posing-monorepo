import XCTest
@testable import iosApp

final class EndpointPolicyTests: XCTestCase {
    func testValidateAcceptsHttps() {
        XCTAssertEqual(EndpointPolicy.validate(raw: "https://api.example.com"), "https://api.example.com")
    }

    func testValidateRejectsBlank() {
        XCTAssertNil(EndpointPolicy.validate(raw: "   "))
    }

    func testValidateRejectsEmbeddedWhitespace() {
        XCTAssertNil(EndpointPolicy.validate(raw: "https://api.example.com bad"))
    }

    func testResolvePrefersFetchOverCache() {
        let result = EndpointPolicy.resolve(
            defaultUrl: "https://default",
            cachedRaw: "https://cache",
            fetchedRaw: "https://fetch"
        )
        XCTAssertEqual(result, "https://fetch")
    }

    func testResolveFallsBackToDefault() {
        let result = EndpointPolicy.resolve(defaultUrl: "https://default", cachedRaw: nil, fetchedRaw: "not a url")
        XCTAssertEqual(result, "https://default")
    }
}
