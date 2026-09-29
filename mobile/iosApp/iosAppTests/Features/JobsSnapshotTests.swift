import SwiftUI
import XCTest
@testable import iosApp

private final class SnapshotStubJobsService: ObservableObject, JobsServing, @unchecked Sendable {
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
    func submit(image: Data, fileName: String, draft: PoseDraft) async throws -> String { "job_snapshot_1" }
    func retry(id: String) async throws {}
    func hide(id: String) async throws {}
    func getGuide(id: String) async throws -> GuidePose { throw JobsError.notFound }
}

@MainActor
final class JobsSnapshotTests: XCTestCase {
    private let outputDirectory = URL(fileURLWithPath: "/Users/phamnhuphong/Git/ai-pose/plans/260925-server-authoritative-jobs/screens")

    override func setUp() {
        super.setUp()
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    private func renderAndSave<Content: View>(view: Content, filename: String) {
        let host = UIHostingController(rootView: view)
        let size = CGSize(width: 390, height: 844)
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1.0 // 390x844 exact points
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }

        XCTAssertEqual(image.size.width, 390)
        XCTAssertEqual(image.size.height, 844)

        if let data = image.pngData() {
            let fileURL = outputDirectory.appendingPathComponent(filename)
            try? data.write(to: fileURL)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        } else {
            XCTFail("Failed to render PNG data for \(filename)")
        }
    }

    func testCaptureAddPoseFormScreenshot() {
        let stub = SnapshotStubJobsService()
        let vm = AddPoseViewModel(jobsService: stub)
        vm.name = "Standing Hero Pose"
        vm.tagsText = "standing, hero, balance"
        vm.descriptionText = "Stand tall with feet shoulder-width apart, arms raised confidently."

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1.0
        let placeholderImg = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200), format: format).image { ctx in
            UIColor.systemGray5.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }
        vm.selectedImage = placeholderImg
        vm.selectedImageData = placeholderImg.jpegData(compressionQuality: 0.85)
        vm.selectedFileName = "hero_pose.jpg"

        XCTAssertTrue(vm.isFormValid)
        XCTAssertEqual(vm.parsedTags, ["standing", "hero", "balance"])

        let posesModel = PosesViewModel(service: PreviewPoseService())
        let view = AddPoseScreen(viewModel: vm, posesModel: posesModel)

        renderAndSave(view: view, filename: "01-add-pose-form.png")
    }

    func testCaptureAddPoseProcessingScreenshot() {
        let stub = SnapshotStubJobsService()
        let vm = AddPoseViewModel(jobsService: stub)
        vm.name = "Warrior Stance"
        vm.submittedJobId = "job_proc_123"
        vm.currentJobStatus = "processing"

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1.0
        let placeholderImg = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200), format: format).image { ctx in
            UIColor.systemGray4.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }
        vm.selectedImage = placeholderImg

        XCTAssertEqual(vm.currentJobStatus, "processing")
        XCTAssertEqual(vm.submittedJobId, "job_proc_123")

        let posesModel = PosesViewModel(service: PreviewPoseService())
        let view = AddPoseScreen(viewModel: vm, posesModel: posesModel)

        renderAndSave(view: view, filename: "02-add-pose-processing.png")
    }

    func testCaptureJobsProcessingScreenshot() {
        let stub = SnapshotStubJobsService()
        stub.inProgress = [
            JobRow(jobId: "j1", name: "Warrior Stance", status: .processing, createdAt: "2026-09-26T12:00:00Z"),
            JobRow(jobId: "j2", name: "Tree Balance Pose", status: .queued, createdAt: "2026-09-26T12:01:00Z")
        ]
        stub.activeCount = 2
        stub.isOffline = false

        XCTAssertEqual(stub.inProgress.count, 2)
        XCTAssertEqual(stub.activeCount, 2)

        let posesModel = PosesViewModel(service: PreviewPoseService())
        let view = JobsScreen(jobsService: stub, posesModel: posesModel, initialTab: .processing)

        renderAndSave(view: view, filename: "03-jobs-processing.png")
    }

    func testCaptureJobsFinishScreenshot() {
        let stub = SnapshotStubJobsService()
        stub.finished = [
            JobRow(jobId: "j3", name: "Cobra Stretch", status: .succeeded, poseId: "pose_3", createdAt: "2026-09-26T11:50:00Z"),
            JobRow(jobId: "j4", name: "Dancing Shiva", status: .failed, errorMessage: "Background removal failed", createdAt: "2026-09-26T11:40:00Z")
        ]
        stub.isOffline = false

        XCTAssertEqual(stub.finished.count, 2)
        XCTAssertEqual(stub.finished[0].status, .succeeded)
        XCTAssertEqual(stub.finished[1].status, .failed)

        let posesModel = PosesViewModel(service: PreviewPoseService())
        let view = JobsScreen(jobsService: stub, posesModel: posesModel, initialTab: .finish)

        renderAndSave(view: view, filename: "04-jobs-finish.png")
    }

    func testCaptureJobsEmptyScreenshot() {
        let stub = SnapshotStubJobsService()
        stub.inProgress = []
        stub.finished = []
        stub.isOffline = false

        XCTAssertTrue(stub.inProgress.isEmpty)
        XCTAssertTrue(stub.finished.isEmpty)

        let posesModel = PosesViewModel(service: PreviewPoseService())
        let view = JobsScreen(jobsService: stub, posesModel: posesModel, initialTab: .processing)

        renderAndSave(view: view, filename: "05-jobs-empty.png")
    }

    func testCaptureJobsOfflineScreenshot() {
        let stub = SnapshotStubJobsService()
        stub.inProgress = [
            JobRow(jobId: "j_offline_1", name: "Warrior Stance (Cached)", status: .processing, createdAt: "2026-09-26T12:00:00Z")
        ]
        stub.activeCount = 1
        stub.isOffline = true

        XCTAssertTrue(stub.isOffline)
        XCTAssertEqual(stub.inProgress.count, 1)
        XCTAssertEqual(stub.inProgress[0].name, "Warrior Stance (Cached)")

        let posesModel = PosesViewModel(service: PreviewPoseService())
        let view = JobsScreen(jobsService: stub, posesModel: posesModel, initialTab: .processing)

        renderAndSave(view: view, filename: "06-jobs-offline.png")
    }
}
