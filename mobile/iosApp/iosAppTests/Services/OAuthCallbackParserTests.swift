import XCTest
@testable import iosApp

final class OAuthCallbackParserTests: XCTestCase {
    func testCodeFromQuery() {
        let url = URL(string: "aipose://auth?code=abc123")!
        XCTAssertEqual(OAuthCallbackParser.code(from: url), "abc123")
    }

    func testCodeFromFragment() {
        let url = URL(string: "aipose://auth#code=frag456")!
        XCTAssertEqual(OAuthCallbackParser.code(from: url), "frag456")
    }

    func testQueryCodePreferredOverFragment() {
        let url = URL(string: "aipose://auth?code=query#code=fragment")!
        XCTAssertEqual(OAuthCallbackParser.code(from: url), "query")
    }

    func testRejectsWrongScheme() {
        let url = URL(string: "https://evil?code=abc")!
        XCTAssertNil(OAuthCallbackParser.code(from: url))
    }

    func testRejectsDuplicateCode() {
        let url = URL(string: "aipose://auth?code=a&code=b")!
        XCTAssertNil(OAuthCallbackParser.code(from: url))
    }

    func testProviderErrorFromQuery() {
        let url = URL(string: "aipose://auth?error=access_denied&error_description=User%20denied")!
        XCTAssertEqual(OAuthCallbackParser.providerError(from: url), "User denied")
    }

    func testProviderErrorFromFragment() {
        let url = URL(string: "aipose://auth#error=denied")!
        XCTAssertEqual(OAuthCallbackParser.providerError(from: url), "denied")
    }
}
