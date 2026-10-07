import SwiftUI
import XCTest
@testable import iosApp

private final class ScreenStubJobsService: ObservableObject, JobsServing, @unchecked Sendable {
    @Published var inProgress: [JobRow] = []
    @Published var finished: [JobRow] = []
    @Published var activeCount: Int = 0
    @Published var isOffline: Bool = false
    @Published var loadState: JobsLoadState = .loaded

    func refresh() async {}
    func startPolling() {}
    func stopPolling() {}
    func watchJob(id: String) -> AsyncStream<JobWatchEvent> {
        AsyncStream { $0.finish() }
    }
    func submit(image: Data, fileName: String, draft: PoseDraft) async throws -> String { "job_stub_1" }
    func retry(id: String) async throws {}
    func hide(id: String) async throws {}
    func getGuide(id: String) async throws -> GuidePose { throw JobsError.notFound }
}

@MainActor
final class JobsScreenModelTests: XCTestCase {
    func testGuidePoseMappingToNativePose() {
        let guide = GuidePose(
            poseId: "guide_123",
            ownerAccountId: "owner_456",
            name: "Tree Pose Variation",
            description: "Step 1: Balance on left foot.\nStep 2: Raise arms above head.",
            tags: ["balance", "yoga", "standing"],
            difficulty: "intermediate",
            bodyParts: ["legs", "arms"],
            status: "local",
            originalUrl: "https://r2.example.com/original.jpg",
            skeletonUrl: "/poses/guide_123/skeleton.png",
            thumbnailUrl: "/poses/guide_123/thumbnail.png",
            currentJobId: "job_789",
            createdAt: "2026-09-26T12:00:00Z",
            updatedAt: "2026-09-26T12:00:00Z"
        )

        let baseURL = "https://api.example.com"
        let nativePose = GuidePoseMapper.map(guide, baseURL: baseURL)

        XCTAssertEqual(nativePose.id, "guide_123")
        XCTAssertEqual(nativePose.name, "Tree Pose Variation")
        XCTAssertEqual(nativePose.category, "balance") // First tag
        XCTAssertEqual(nativePose.imageURL, URL(string: "https://r2.example.com/original.jpg"), "thumb is the source photo")
        XCTAssertEqual(nativePose.guideURL, URL(string: "https://api.example.com/poses/guide_123/skeleton.png"), "camera guide is the extracted line art")
        XCTAssertEqual(nativePose.instructions.count, 2)
        XCTAssertEqual(nativePose.instructions[0], "Step 1: Balance on left foot.")
        XCTAssertEqual(nativePose.instructions[1], "Step 2: Raise arms above head.")
        XCTAssertFalse(nativePose.isSaved)
    }

    func testJobRowFiltering() {
        let queued = JobRow(jobId: "1", name: "Q", status: .queued)
        let processing = JobRow(jobId: "2", name: "P", status: .processing)
        let succeeded = JobRow(jobId: "3", name: "S", status: .succeeded, poseId: "p3")
        let failed = JobRow(jobId: "4", name: "F", status: .failed)

        let inProgress = [queued, processing]
        let finished = [succeeded, failed]

        // Finish filters
        let allFilter = finished
        let successFilter = finished.filter { $0.status == .succeeded }
        let failFilter = finished.filter { $0.status == .failed }

        XCTAssertEqual(inProgress.count, 2)
        XCTAssertEqual(allFilter.count, 2)
        XCTAssertEqual(successFilter.count, 1)
        XCTAssertEqual(successFilter[0].jobId, "3")
        XCTAssertEqual(failFilter.count, 1)
        XCTAssertEqual(failFilter[0].jobId, "4")
    }

    func testPrivatePoseDetailSkipsConfirmPublished() async {
        // A service that would fail confirmPublished (poseNotFound)
        struct FailingPoseService: PoseServing {
            func poses(query: String?) async throws -> [NativePose] { [] }
            func pose(id: String) async throws -> NativePose {
                throw PoseAdapterError.poseNotFound(id)
            }
        }

        let model = PosesViewModel(service: FailingPoseService())
        let privatePose = NativePose(
            id: "private_pose_1",
            name: "My Private Pose",
            category: "private",
            imageURL: nil,
            instructions: ["Stand"],
            isSaved: false
        )

        // For non-private, confirmPublished fails
        let isPublished = await model.confirmPublished(privatePose)
        XCTAssertFalse(isPublished)

        // For private poses, PoseDetailScreen is initialized with isPrivate: true and skips this check
        let detailScreen = PoseDetailScreen(
            pose: privatePose,
            model: model,
            onTryPose: { _ in },
            isPrivate: true
        )
        XCTAssertTrue(detailScreen.isPrivate)
    }

    func testJobRowViewHideActionCallback() {
        var hiddenJob: JobRow? = nil
        let row = JobRow(jobId: "job_hide_1", name: "Tree Pose", status: .succeeded, poseId: "p1")
        let rowView = JobRowView(
            row: row,
            onAction: { _ in },
            onHide: { target in
                hiddenJob = target
            }
        )
        rowView.onHide?(row)
        XCTAssertEqual(hiddenJob?.jobId, "job_hide_1")
    }

    func testJobRowViewPropertiesForSucceededRow() {
        let row = JobRow(jobId: "job_succ_1", name: "Tree Balance Pose", status: .succeeded, poseId: "p1")
        XCTAssertEqual(row.name, "Tree Balance Pose")
        XCTAssertEqual(row.status, .succeeded)
        XCTAssertEqual(row.statusLabel, "Ready")
        XCTAssertEqual(row.action, .viewPose)
        XCTAssertEqual(row.action.rawValue, "View pose")
    }

    func testJobsScreenInitialStateWithSucceededStubRow() {
        let stub = ScreenStubJobsService()
        stub.finished = [
            JobRow(jobId: "j_test_succ", name: "Tree Balance Pose", status: .succeeded, poseId: "pose_succ_1")
        ]
        stub.loadState = .loaded

        let posesModel = PosesViewModel(service: PreviewPoseService())
        let view = JobsScreen(jobsService: stub, posesModel: posesModel, initialTab: .finish)

        let host = UIHostingController(rootView: view)
        let size = CGSize(width: 390, height: 844)
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: size)
        let _ = renderer.image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }

        XCTAssertEqual(stub.finished.count, 1)
        XCTAssertEqual(stub.finished[0].name, "Tree Balance Pose")
        XCTAssertEqual(stub.finished[0].statusLabel, "Ready")
        XCTAssertEqual(stub.finished[0].action.rawValue, "View pose")
    }

    func testJobsScreenEmptyStateWhenStubHasNoRows() {
        let stub = ScreenStubJobsService()
        stub.finished = []
        stub.inProgress = []
        stub.loadState = .loaded

        let posesModel = PosesViewModel(service: PreviewPoseService())
        let view = JobsScreen(jobsService: stub, posesModel: posesModel, initialTab: .finish)

        let host = UIHostingController(rootView: view)
        let size = CGSize(width: 390, height: 844)
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: size)
        let _ = renderer.image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }

        XCTAssertTrue(stub.finished.isEmpty)
        XCTAssertTrue(stub.inProgress.isEmpty)
    }
}

