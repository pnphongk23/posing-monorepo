import XCTest
@testable import iosApp

/// The camera-local pose-picker bottom sheet (`.nb-pose-picker-sheet`, `guide-picker.js`).
/// These tests cover the view-model logic only; the sheet itself is exercised by the
/// Maestro UI-parity flow (`scripts/maestro/ui-parity.yaml`, DL-B).
@MainActor
final class PosePickerViewModelTests: XCTestCase {
    func testLoadsCatalogPosesFromService() async {
        let poses = [
            samplePose(id: "a", name: "Alpha"),
            samplePose(id: "b", name: "Beta"),
            samplePose(id: "c", name: "Charlie"),
        ]
        let model = PosePickerViewModel(service: StubPoseService(poses: poses))
        await model.load()
        guard case .loaded(let loaded) = model.state else {
            return XCTFail("Expected loaded, got \(model.state)")
        }
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded.map(\.id), ["a", "b", "c"])
    }

    func testEmptyCatalogMapsToEmptyState() async {
        let model = PosePickerViewModel(service: StubPoseService(poses: []))
        await model.load()
        guard case .empty = model.state else { return XCTFail("Expected empty") }
    }

    func testFailedLoadMapsToFailedState() async {
        let model = PosePickerViewModel(service: FailingPoseService())
        await model.load()
        guard case .failed = model.state else { return XCTFail("Expected failed") }
    }

    /// The first paint under a new query: the local matcher narrows what the sheet already has, before the
    /// server answers, and keeps doing so offline (`CameraPickerServerSearchTests` covers the request itself).
    func testTheFirstPaintUsesTheLocalMatcherWhileTheAnswerIsOut() async {
        let model = PosePickerViewModel(
            service: StubPoseService(poses: [
                samplePose(id: "a", name: "Warrior II"),
                samplePose(id: "b", name: "Downward Dog"),
            ]),
            searchDebounceNanoseconds: .max
        )
        await model.load()
        model.query = "  WARRIOR  "
        XCTAssertEqual(model.filteredPoses.map(\.id), ["a"])
    }

    /// `guide-picker.js`: typing into the field only re-renders from the loaded catalogue, and
    /// `pose-picker-search__clear` resets to the full grid without refetching.
    func testClearSearchRestoresFullCatalogueWithoutRefetching() async {
        let poses = [
            samplePose(id: "a", name: "Alpha"),
            samplePose(id: "b", name: "Beta"),
        ]
        let service = CountingPoseService(poses: poses)
        let model = PosePickerViewModel(service: service, searchDebounceNanoseconds: .max)

        await model.load()
        model.query = "alp"
        XCTAssertEqual(model.filteredPoses.map(\.id), ["a"])
        model.clearSearch()
        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.filteredPoses.map(\.id), ["a", "b"])
        XCTAssertEqual(service.fetchCount(), 1, "clear-search must not refetch")
    }

    /// The fallback the sheet paints while the server answers (and online-only failures aside, the whole
    /// offline answer) is the shared matcher the Saved screen uses — never a second, weaker filter.
    func testTheFirstPaintFilterIsTheSharedNameMatcher() async {
        let poses = [
            samplePose(id: "a", name: "Warrior II"),
            samplePose(id: "b", name: "Downward Dog"),
            samplePose(id: "c", name: "Café lean"),
        ]
        let model = PosePickerViewModel(service: StubPoseService(poses: poses), searchDebounceNanoseconds: .max)
        await model.load()

        for query in ["warrior", "  WARRIOR  ", "dog", "CAFÉ", "café", "  ", "", "zzz"] {
            model.query = query
            XCTAssertEqual(
                model.filteredPoses.map(\.id),
                PoseAdapterMerge.filterSavedLocally(poses, query: query).map(\.id),
                "the sheet answers \"\(query)\" exactly like the shared filter"
            )
        }
    }

    func testSelectionCallbackReceivesNativePose() {
        var selected: NativePose?
        let pose = samplePose(id: "pick-me", name: "Pick Me")
        let onSelect: (NativePose) -> Void = { selected = $0 }
        onSelect(pose)
        XCTAssertEqual(selected?.id, "pick-me")
        XCTAssertEqual(selected?.name, "Pick Me")
    }
}

private func samplePose(id: String, name: String) -> NativePose {
    NativePose(
        id: id,
        name: name,
        category: "Standing",
        imageURL: URL(string: "https://example.com/\(id).jpg"),
        instructions: ["Step one"],
        isSaved: false
    )
}

private struct StubPoseService: PoseServing {
    let poses: [NativePose]
    func poses(query: String?) async throws -> [NativePose] { poses }
    func pose(id: String) async throws -> NativePose { poses.first { $0.id == id } ?? poses[0] }
}

private struct FailingPoseService: PoseServing {
    func poses(query: String?) async throws -> [NativePose] { throw NSError(domain: "test", code: 1) }
    func pose(id: String) async throws -> NativePose { throw NSError(domain: "test", code: 1) }
}

private final class CountingPoseService: PoseServing, @unchecked Sendable {
    let poses: [NativePose]
    private let lock = NSLock()
    private var fetches = 0

    init(poses: [NativePose]) {
        self.poses = poses
    }

    func fetchCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return fetches
    }

    func poses(query: String?) async throws -> [NativePose] {
        incrementFetches()
        return poses
    }

    private nonisolated func incrementFetches() {
        lock.lock()
        defer { lock.unlock() }
        fetches += 1
    }

    func pose(id: String) async throws -> NativePose { poses.first { $0.id == id } ?? poses[0] }
}
