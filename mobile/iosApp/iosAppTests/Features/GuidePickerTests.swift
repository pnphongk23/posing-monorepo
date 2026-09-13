import XCTest
@testable import iosApp

final class GuidePickerTests: XCTestCase {
    @MainActor func testLoadsCatalogPosesFromService() async {
        let poses = [
            sampleGuidePose(id: "a", name: "Alpha"),
            sampleGuidePose(id: "b", name: "Beta"),
            sampleGuidePose(id: "c", name: "Charlie"),
        ]
        let model = GuidePickerViewModel(service: StubGuidePoseService(poses: poses))
        await model.load()
        guard case .loaded(let loaded) = model.state else {
            return XCTFail("Expected loaded, got \(model.state)")
        }
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded.map(\.id), ["a", "b", "c"])
    }

    @MainActor func testEmptyCatalogMapsToEmptyState() async {
        let model = GuidePickerViewModel(service: StubGuidePoseService(poses: []))
        await model.load()
        guard case .empty = model.state else { return XCTFail("Expected empty") }
    }

    @MainActor func testFailedLoadMapsToFailedState() async {
        let model = GuidePickerViewModel(service: FailingGuidePoseService())
        await model.load()
        guard case .failed = model.state else { return XCTFail("Expected failed") }
    }

    @MainActor func testSelectionCallbackReceivesNativePose() async {
        var selected: NativePose?
        let pose = sampleGuidePose(id: "pick-me", name: "Pick Me")
        let onSelect: (NativePose) -> Void = { selected = $0 }
        onSelect(pose)
        XCTAssertEqual(selected?.id, "pick-me")
        XCTAssertEqual(selected?.name, "Pick Me")
    }
}

private func sampleGuidePose(id: String, name: String) -> NativePose {
    NativePose(
        id: id,
        name: name,
        category: "Standing",
        imageURL: URL(string: "https://example.com/\(id).jpg"),
        instructions: ["Step one"],
        isSaved: false
    )
}

private struct StubGuidePoseService: PoseServing {
    let poses: [NativePose]
    func poses(query: String?) async throws -> [NativePose] { poses }
    func pose(id: String) async throws -> NativePose { poses.first { $0.id == id } ?? poses[0] }
}

private struct FailingGuidePoseService: PoseServing {
    func poses(query: String?) async throws -> [NativePose] { throw NSError(domain: "test", code: 1) }
    func pose(id: String) async throws -> NativePose { throw NSError(domain: "test", code: 1) }
}
