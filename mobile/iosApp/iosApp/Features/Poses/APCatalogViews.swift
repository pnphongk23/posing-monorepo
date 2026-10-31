// Design-B catalogue surfaces: the Poses home grid/cards, the category filter row, the paged footer
// and the state panel. Same behaviour as the legacy `PoseCard` / `PoseGrid` / `PagingFooter`, on the
// `AP` token layer and faithful to artboards 02/03.
//
// The legacy views stay in place: `PoseResultsList` still drives the Saved slice, which is a later
// migration, so this file adds the AP variants instead of rewriting the shared ones.

import SwiftUI
import UIKit

// MARK: - Layout rules

/// Grid reflow and masonry assignment for the catalogue.
enum APGridLayout {
    static let columnSpacing: CGFloat = AP.Space.space8
    static let rowSpacing: CGFloat = AP.Space.space16
    static let defaultAspectRatio: CGFloat = 1
    /// Artwork decode bound: one column wide, at most 1.25× as tall as wide.
    static let minimumDownsampleAspectRatio: CGFloat = 0.8
    static let labelHeightForBalancing: CGFloat = 52
    /// Scroll clearance under the shell dock: pill (60) + bottom inset (16) + home indicator (34).
    static let dockClearance: CGFloat = 110

    /// Two columns at the default sizes, one at AX1 and above (artboard `02-poses-home-loaded-ax3`):
    /// at Accessibility sizes a 2-up grid halves the column and clips the title.
    static func columns(for size: DynamicTypeSize) -> Int {
        size.isAccessibilitySize ? 1 : 2
    }

    static func columnWidth(screenWidth: CGFloat, columns: Int, inset: CGFloat = AP.Space.space16) -> CGFloat {
        let safeColumns = max(1, columns)
        let contentWidth = max(1, screenWidth - 2 * inset)
        let gaps = CGFloat(safeColumns - 1) * columnSpacing
        return max(1, (contentWidth - gaps) / CGFloat(safeColumns))
    }

    /// Column width for the device screen; the grid needs it before it can size its artwork.
    @MainActor static func screenColumnWidth(columns: Int) -> CGFloat {
        let width = UIScreen.main.bounds.width
        return columnWidth(screenWidth: width > 0 ? width : 390, columns: columns)
    }

    /// Assign each item in source order to the column with the lower accumulated height.
    /// With one column every item lands in column 0, which is exactly the AX reflow.
    static func columnAssignments(
        for aspectRatios: [CGFloat],
        columnWidth: CGFloat,
        columns: Int,
        itemSpacing: CGFloat = rowSpacing,
        labelHeight: CGFloat = labelHeightForBalancing,
        labelSpacing: CGFloat = 0
    ) -> [Int] {
        guard !aspectRatios.isEmpty else { return [] }
        let count = max(1, columns)
        let width = max(1, columnWidth.isFinite ? columnWidth : 1)
        var heights = [CGFloat](repeating: 0, count: count)
        var seen = [Int](repeating: 0, count: count)

        return aspectRatios.map { ratio in
            // `min(by:)` keeps the lowest index on a tie, so source order is stable.
            let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            let safeRatio = ratio.isFinite && ratio > 0 ? ratio : defaultAspectRatio
            let gap = seen[column] == 0 ? 0 : itemSpacing
            heights[column] += width / safeRatio + labelHeight + labelSpacing + gap
            seen[column] += 1
            return column
        }
    }

    @MainActor static func artworkPoints(columns: Int) -> CGSize {
        let width = screenColumnWidth(columns: columns)
        return CGSize(width: width, height: width / minimumDownsampleAspectRatio)
    }
}

// MARK: - Category filter

/// Multi-select category filter over the loaded catalogue. Client-side on purpose: the paged service
/// has no category parameter, and inventing one would change what a page means. The selection only
/// narrows the rows already fetched, and a page that arrives later is filtered the same way.
struct APCategoryFilter: Equatable {
    static let allTitle = "All"
    static let emptyTitle = "No poses match"
    static let recoveryTitle = "Clear filters"

    private(set) var selected: Set<String> = []

    var isActive: Bool { !selected.isEmpty }
    var isEmpty: Bool { selected.isEmpty }

    /// Categories present in the list, unique and in first-appearance order, so the row cannot
    /// reshuffle when a later page arrives.
    static func categories(in poses: [NativePose]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for pose in poses {
            let title = pose.category.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, seen.insert(title).inserted else { continue }
            ordered.append(title)
        }
        return ordered
    }

    func isSelected(_ category: String) -> Bool { selected.contains(category) }

    mutating func toggle(_ category: String) {
        if selected.contains(category) {
            selected.remove(category)
        } else {
            selected.insert(category)
        }
    }

    mutating func clear() { selected.removeAll() }

    func matches(_ pose: NativePose) -> Bool {
        guard !selected.isEmpty else { return true }
        return selected.contains(pose.category)
    }

    func apply(to poses: [NativePose]) -> [NativePose] {
        guard !selected.isEmpty else { return poses }
        return poses.filter(matches)
    }

    /// Copy for the no-match panel: names the styles that are selected, so the panel explains itself.
    var message: String {
        let titles = selected.sorted()
        switch titles.count {
        case 0:
            return "Try a different category."
        case 1:
            return "Nothing fits \(titles[0]). Try removing the filter."
        case 2:
            return "Nothing fits \(titles[0]) and \(titles[1]) together. Try removing a filter."
        default:
            return "Nothing fits \(titles.count) styles together. Try removing a filter."
        }
    }
}

// MARK: - Presentation rule

/// Which panel the catalogue shows. Pure, so the state a screen renders for a given model state is
/// testable without driving the view.
enum APCatalogPresentation: Equatable {
    case loading
    case failed
    case empty
    case noMatch
    case grid
}

enum APCatalogPresentationRule {
    static func presentation(
        for state: Loadable<[NativePose]>,
        hasVisiblePoses: Bool,
        isFilterActive: Bool
    ) -> APCatalogPresentation {
        switch state {
        case .idle, .loading:
            return .loading
        case .failed:
            return .failed
        case .empty:
            return .empty
        case .loaded(let poses):
            guard !poses.isEmpty else { return .empty }
            if hasVisiblePoses { return .grid }
            return isFilterActive ? .noMatch : .empty
        }
    }
}

// MARK: - Paging footer rule

enum APPagingFooterPhase: Equatable {
    case hidden
    case loading
    case loadMore
    case failed
    case end
}

enum APPagingFooterRule {
    static let loadMore = "Load more"
    static let loading = "Loading more poses…"
    static let failed = "Couldn't load more poses."
    static let retry = "Retry"
    static let end = "You've reached the end"

    static func phase(
        error: String?,
        hasMore: Bool,
        remainingAutoFetches: Int,
        hasRows: Bool
    ) -> APPagingFooterPhase {
        if error != nil { return .failed }
        if hasMore { return remainingAutoFetches > 0 ? .loading : .loadMore }
        return hasRows ? .end : .hidden
    }

    static func countLabel(_ count: Int) -> String {
        count == 1 ? "Showing 1 pose" : "Showing \(count) poses"
    }
}
