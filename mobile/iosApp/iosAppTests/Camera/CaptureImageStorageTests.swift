import XCTest
@testable import iosApp

final class CaptureImageStorageTests: XCTestCase {
    func testWriteVerifyAndDeleteRoundTrip() {
        let storage = CaptureImageStorage()
        let bytes = Data("jpeg-bytes".utf8)
        let filename = storage.writeJpeg(bytes, captureId: "abc-123")
        XCTAssertEqual(filename, "capture_abc-123.jpg")
        XCTAssertTrue(storage.verify(filename: filename!))
        storage.delete(filename: filename!)
        XCTAssertFalse(storage.verify(filename: filename!))
    }

    func testEmptyBytesAreRejected() {
        let storage = CaptureImageStorage()
        XCTAssertNil(storage.writeJpeg(Data(), captureId: "empty"))
    }
}
