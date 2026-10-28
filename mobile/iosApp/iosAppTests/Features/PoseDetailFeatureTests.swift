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

    @MainActor func testDetailHeroCardTakesCachedPhotoRatioWithNoLetterbox() {
        let pose = sampleDetailPose
        let cache = PoseAspectRatioCache.shared
        cache.resetForTesting()
        defer { cache.resetForTesting() }

        // Cold open (deep link / Jobs / saved list before any decode): prototype card, and the
        // shimmer is drawn at exactly that size.
        XCTAssertEqual(
            PoseDetailLayoutMetrics.heroAspectRatio(cachedPhotoRatio: cache.ratios[pose.id]),
            PoseDetailLayoutMetrics.heroCardAspectRatio,
            accuracy: 0.0001
        )

        // The decode the hero already performs settles the card on the photo's own box: the drawn
        // card ratio equals the photo ratio, so no edge of the card is padding.
        cache.updateRatio(width: 1200, height: 1600, for: pose.id)
        let photoRatio = CGFloat(1200) / CGFloat(1600)
        let heroRatio = PoseDetailLayoutMetrics.heroAspectRatio(cachedPhotoRatio: cache.ratios[pose.id])
        XCTAssertEqual(heroRatio, photoRatio, accuracy: 0.0001)
        XCTAssertEqual(cache.ratio(for: pose.id), photoRatio, accuracy: 0.0001)
        XCTAssertEqual(
            PoseDetailLayoutMetrics.heroCardWidth / heroRatio,
            PoseDetailLayoutMetrics.heroCardWidth * 1600 / 1200,
            accuracy: 0.5
        )
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
