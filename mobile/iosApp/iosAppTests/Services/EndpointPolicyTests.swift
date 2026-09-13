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

final class RuntimeConfigResolverTests: XCTestCase {
    func testFetchSuccessApplied() {
        let resolution = RuntimeConfigResolver.resolve(
            defaultUrl: "https://default",
            cachedRaw: nil,
            fetchResult: .success("https://fetch")
        )
        XCTAssertEqual(resolution.url, "https://fetch")
        XCTAssertEqual(resolution.source, .fetch)
        XCTAssertEqual(resolution.outcome, .applied)
    }

    func testTimeoutUsesCache() {
        let resolution = RuntimeConfigResolver.resolve(
            defaultUrl: "https://default",
            cachedRaw: "https://cache",
            fetchResult: .timeout
        )
        XCTAssertEqual(resolution.url, "https://cache")
        XCTAssertEqual(resolution.source, .cache)
        XCTAssertEqual(resolution.outcome, .timeout)
    }

    func testUnavailableUsesDefault() {
        let resolution = RuntimeConfigResolver.resolve(
            defaultUrl: "https://default",
            cachedRaw: nil,
            fetchResult: .unavailable
        )
        XCTAssertEqual(resolution.url, "https://default")
        XCTAssertEqual(resolution.source, .default)
        XCTAssertEqual(resolution.outcome, .unavailable)
    }
}
