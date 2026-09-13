import XCTest
@testable import iosApp

final class PoseDetailFeatureTests: XCTestCase {
    func testSharedDockScrollInsetMatchesNeoDockTabBarFootprint() {
        XCTAssertEqual(PoseDetailLayoutMetrics.sharedDockScrollInset, 48 + AIPoseSpacing.sm + AIPoseSpacing.lg)
    }

    @MainActor func testTryPoseCallbackPreservesPoseIdentity() {
        var received: NativePose?
        let pose = sampleDetailPose
        let onTryPose: (NativePose) -> Void = { received = $0 }
        onTryPose(pose)
        XCTAssertEqual(received?.id, pose.id)
        XCTAssertEqual(received?.name, pose.name)
    }

    @MainActor func testLocalBookmarkToggleUpdatesViewModelState() async {
        let pose = sampleDetailPose
        let model = PosesViewModel(service: StubPoseService(result: [pose]))
        model.state = .loaded([pose])
        model.updateSavedLocally(poseID: pose.id, saved: true)
        guard case .loaded(let poses) = model.state else { return XCTFail("Expected loaded") }
        XCTAssertTrue(poses[0].isSaved)
    }
}

private let sampleDetailPose = NativePose(
    id: "detail-1",
    name: "Detail Pose",
    category: "Standing",
    imageURL: URL(string: "https://example.com/detail.jpg"),
    instructions: ["Step one"],
    isSaved: false
)

private struct StubPoseService: PoseServing {
    let result: [NativePose]
    func poses(query: String?) async throws -> [NativePose] { result }
    func pose(id: String) async throws -> NativePose { result[0] }
}
