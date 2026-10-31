import XCTest
@testable import iosApp

/// A job row must stay a *container* of accessibility elements: the row summary is one combined
/// element, and the Retry / View pose buttons are separate elements that a UI test can reach by
/// identifier. `children: .combine` on the row swallowed both buttons, so `jobRow.retry.<id>` and
/// `jobRow.viewPose.<id>` never appeared in the accessibility tree.
///
/// Mutation target: put `.accessibilityElement(children: .combine)` back on the row (instead of
/// `.contain`) and `testRowIsAContainerWithOnlyTheTextGroupCombined` goes red — two combined
/// elements, no container, and the row-level `.accessibilityLabel`/`.accessibilityAction` return.
@MainActor
final class JobRowAccessibilityTests: XCTestCase {
    /// The identifiers Maestro/XCUITest tap. They must keep the per-job suffix so a list with several
    /// rows stays addressable.
    func testActionIdentifiersKeepTheJobId() {
        XCTAssertEqual(JobRowView.retryIdentifier(jobId: "job_1"), "jobRow.retry.job_1")
        XCTAssertEqual(JobRowView.viewPoseIdentifier(jobId: "job_1"), "jobRow.viewPose.job_1")
    }

    /// The summary element keeps reading name, state and action, exactly as the pre-container row did.
    func testRowSummaryStillNamesTheAction() {
        let failed = JobRow(jobId: "job_f", name: "Tree Pose", status: .failed)
        XCTAssertEqual(JobRowView.accessibilitySummary(for: failed), "Tree Pose, Failed, Retry")

        let succeeded = JobRow(jobId: "job_s", name: "Warrior Pose", status: .succeeded, poseId: "pose_1")
        XCTAssertEqual(JobRowView.accessibilitySummary(for: succeeded), "Warrior Pose, Ready, View pose")

        let processing = JobRow(jobId: "job_p", name: "Hero Pose", status: .processing)
        XCTAssertEqual(JobRowView.accessibilitySummary(for: processing), "Hero Pose, Processing")
    }

    /// Source-level, because SwiftUI's accessibility tree is not materialised for a unit-test host.
    /// Two things must hold at once: the row is a container, and the only combined element is the
    /// text group (which is where the `.accessibilityLabel` lives).
    func testRowIsAContainerWithOnlyTheTextGroupCombined() throws {
        let source = try jobRowViewSource()
        let lines = source.components(separatedBy: .newlines)

        let combineLines = lines.enumerated().filter { $0.element.contains(".accessibilityElement(children: .combine)") }
        let containLines = lines.enumerated().filter { $0.element.contains(".accessibilityElement(children: .contain)") }

        XCTAssertEqual(
            combineLines.count, 1,
            "exactly the text group combines; a second `.combine` means the row swallowed its buttons again"
        )
        XCTAssertEqual(
            containLines.count, 1,
            "the row itself must be `.contain`, so the action button stays its own element"
        )

        let combined = try XCTUnwrap(combineLines.first?.offset)
        let container = try XCTUnwrap(containLines.first?.offset)
        XCTAssertLessThan(
            combined, container,
            "the combined element must be the inner text group, applied before the row's container modifier"
        )

        // The row modifier chain must end there: a label or the Remove action chained onto the
        // container is not read, and re-adding the summary to the row is the regression this pins.
        let afterContainer = lines[(container + 1)...]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("//") }
        XCTAssertEqual(
            afterContainer, "}",
            "nothing may be chained onto the row container — the summary and Remove belong to the text group"
        )
        XCTAssertTrue(
            lines[combined...container].joined(separator: "\n").contains(".accessibilityLabel(Self.accessibilitySummary(for: row))"),
            "the combined text group carries the row summary"
        )
        XCTAssertTrue(
            lines[combined...container].joined(separator: "\n").contains(".accessibilityAction(named: \"Remove\")"),
            "the Remove affordance follows the summary element it belongs to"
        )
    }

    /// The identifiers must sit on the buttons (via the helpers this test asserts above), inside the
    /// container — not on the row, where they would collide with the summary element.
    func testActionButtonsCarryTheirIdentifiers() throws {
        let source = try jobRowViewSource()

        XCTAssertTrue(
            source.contains(".accessibilityIdentifier(Self.retryIdentifier(jobId: row.jobId))"),
            "the Retry button carries jobRow.retry.<jobId>"
        )
        XCTAssertTrue(
            source.contains(".accessibilityIdentifier(Self.viewPoseIdentifier(jobId: row.jobId))"),
            "the View pose button carries jobRow.viewPose.<jobId>"
        )
        XCTAssertEqual(
            source.components(separatedBy: ".accessibilityIdentifier(").count - 1, 2,
            "only the two action buttons are addressable; the row summary is found by label"
        )
    }

    private func jobRowViewSource() throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Features
                .deletingLastPathComponent() // iosAppTests
                .deletingLastPathComponent() // iosApp (project dir)
                .appendingPathComponent("iosApp/Features/Jobs/JobRowView.swift"),
            encoding: .utf8
        )
    }
}
