import SwiftUI
import XCTest
@testable import iosApp

/// New S1 logic: the AX grid reflow, the category filter semantics, which state panel a model state
/// picks, and which paging footer a paging condition picks. Every case here can fail — mutating the
/// rule under test turns the suite red.
final class APCatalogLogicTests: XCTestCase {
    private func pose(_ id: String, category: String) -> NativePose {
        NativePose(
            id: id,
            name: "Pose \(id)",
            category: category,
            imageURL: nil,
            instructions: [],
            isSaved: false
        )
    }

    // MARK: - Grid reflow

    func testGridKeepsTwoColumnsUntilTheAccessibilitySizes() {
        XCTAssertEqual(APGridLayout.columns(for: .xSmall), 2)
        XCTAssertEqual(APGridLayout.columns(for: .large), 2)
        XCTAssertEqual(APGridLayout.columns(for: .xxxLarge), 2)
        XCTAssertEqual(APGridLayout.columns(for: .accessibility1), 1)
        XCTAssertEqual(APGridLayout.columns(for: .accessibility3), 1)
        XCTAssertEqual(APGridLayout.columns(for: .accessibility5), 1)
    }

    func testSingleColumnAssignmentsPutEveryPoseInTheFirstColumn() {
        let assignments = APGridLayout.columnAssignments(
            for: [0.5, 1, 0.5, 1, 0.5],
            columnWidth: 300,
            columns: 1
        )
        XCTAssertEqual(assignments, [0, 0, 0, 0, 0])
    }

    func testTwoColumnAssignmentsFillTheShorterColumn() {
        // Same numbers as the legacy masonry test: the reflow must not change the 2-up behaviour.
        let assignments = APGridLayout.columnAssignments(
            for: [0.5, 1, 0.5, 1, 0.5],
            columnWidth: 100,
            columns: 2,
            itemSpacing: 0,
            labelHeight: 0
        )
        XCTAssertEqual(assignments, [0, 1, 1, 0, 0])
    }

    func testColumnWidthSplitsTheContentBoxAndItsGaps() {
        // 390 screen, 16 pt insets, one 8 pt gap: two 175 pt columns, one 358 pt column.
        XCTAssertEqual(APGridLayout.columnWidth(screenWidth: 390, columns: 2), 175, accuracy: 0.001)
        XCTAssertEqual(APGridLayout.columnWidth(screenWidth: 390, columns: 1), 358, accuracy: 0.001)
        XCTAssertEqual(APGridLayout.columnWidth(screenWidth: 390, columns: 0), 358, accuracy: 0.001)
    }

    // MARK: - Category filter

    func testCategoriesAreUniqueAndKeepFirstAppearanceOrder() {
        let poses = [
            pose("1", category: "Standing"),
            pose("2", category: "Sitting"),
            pose("3", category: "Standing"),
            pose("4", category: "  "),
            pose("5", category: "Couple")
        ]
        XCTAssertEqual(APCategoryFilter.categories(in: poses), ["Standing", "Sitting", "Couple"])
    }

    func testSelectionTogglesOffAndClears() {
        var filter = APCategoryFilter()
        XCTAssertFalse(filter.isActive)
        filter.toggle("Sitting")
        filter.toggle("Couple")
        XCTAssertTrue(filter.isActive)
        XCTAssertTrue(filter.isSelected("Sitting"))
        XCTAssertEqual(filter.selected, ["Sitting", "Couple"])

        filter.toggle("Sitting")
        XCTAssertFalse(filter.isSelected("Sitting"), "a second tap removes the category")
        XCTAssertEqual(filter.selected, ["Couple"])

        filter.clear()
        XCTAssertFalse(filter.isActive)
    }

    func testFilterNarrowsTheListAndKeepsEverythingWhenEmpty() {
        let poses = [
            pose("1", category: "Standing"),
            pose("2", category: "Sitting"),
            pose("3", category: "Sitting")
        ]
        var filter = APCategoryFilter()
        XCTAssertEqual(filter.apply(to: poses).map(\.id), ["1", "2", "3"], "no selection shows every pose")

        filter.toggle("Sitting")
        XCTAssertEqual(filter.apply(to: poses).map(\.id), ["2", "3"])

        filter.toggle("Couple")
        XCTAssertEqual(filter.apply(to: poses).map(\.id), ["2", "3"], "an unmatched category adds nothing")
    }

    func testNoMatchCopyNamesTheSelectedStyles() {
        var filter = APCategoryFilter()
        XCTAssertEqual(filter.message, "Try a different category.")

        filter.toggle("Sitting")
        XCTAssertEqual(filter.message, "Nothing fits Sitting. Try removing the filter.")

        filter.toggle("Couple")
        XCTAssertEqual(filter.message, "Nothing fits Couple and Sitting together. Try removing a filter.")

        filter.toggle("Standing")
        XCTAssertEqual(filter.message, "Nothing fits 3 styles together. Try removing a filter.")
    }

    // MARK: - State panel selection

    func testCatalogPresentationCoversEveryModelState() {
        let rows = [pose("1", category: "Standing")]

        XCTAssertEqual(rule(.idle, hasVisible: false, filterActive: false), .loading)
        XCTAssertEqual(rule(.loading, hasVisible: false, filterActive: false), .loading)
        XCTAssertEqual(rule(.failed("offline"), hasVisible: false, filterActive: false), .failed)
        XCTAssertEqual(rule(.empty, hasVisible: false, filterActive: false), .empty)
        XCTAssertEqual(rule(.loaded([]), hasVisible: false, filterActive: false), .empty)
        XCTAssertEqual(rule(.loaded(rows), hasVisible: true, filterActive: false), .grid)
        XCTAssertEqual(rule(.loaded(rows), hasVisible: true, filterActive: true), .grid)
        XCTAssertEqual(
            rule(.loaded(rows), hasVisible: false, filterActive: true), .noMatch,
            "a filter that hides every loaded row is a no-match panel, not an empty catalogue"
        )
        XCTAssertEqual(
            rule(.loaded(rows), hasVisible: false, filterActive: false), .empty,
            "no filter and nothing visible can only mean an empty catalogue"
        )
    }

    private func rule(
        _ state: Loadable<[NativePose]>,
        hasVisible: Bool,
        filterActive: Bool
    ) -> APCatalogPresentation {
        APCatalogPresentationRule.presentation(
            for: state,
            hasVisiblePoses: hasVisible,
            isFilterActive: filterActive
        )
    }

    // MARK: - Paging footer

    func testPagingFooterPhaseCoversEveryPagingCondition() {
        XCTAssertEqual(phase(error: "boom", hasMore: true, autoFetches: 3, hasRows: true), .failed)
        XCTAssertEqual(phase(error: "boom", hasMore: false, autoFetches: 0, hasRows: true), .failed)
        XCTAssertEqual(phase(error: nil, hasMore: true, autoFetches: 3, hasRows: true), .loading)
        XCTAssertEqual(phase(error: nil, hasMore: true, autoFetches: 0, hasRows: true), .loadMore)
        XCTAssertEqual(phase(error: nil, hasMore: false, autoFetches: 0, hasRows: true), .end)
        XCTAssertEqual(
            phase(error: nil, hasMore: false, autoFetches: 0, hasRows: false), .hidden,
            "nothing loaded and nothing more to fetch: the footer draws nothing"
        )
    }

    private func phase(error: String?, hasMore: Bool, autoFetches: Int, hasRows: Bool) -> APPagingFooterPhase {
        APPagingFooterRule.phase(
            error: error,
            hasMore: hasMore,
            remainingAutoFetches: autoFetches,
            hasRows: hasRows
        )
    }
}
