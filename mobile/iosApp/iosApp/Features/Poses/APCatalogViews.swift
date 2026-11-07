// Design-B catalogue rules: the AX grid reflow, the category filter, the state-panel choice and the
// paged footer's phase, plus the motion rule. Faithful to artboards 02/03 and shared by the Poses
// home, Search and Saved surfaces.

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

// MARK: - Home header composition (F7)

/// Which actions the Poses header offers. Add pose is a remote-flag action: the flag hides the control
/// entirely instead of showing a disabled one.
enum APHomeHeader {
    static func showsAddPose(isExtractPoseEnabled: Bool) -> Bool {
        isExtractPoseEnabled
    }
}

// MARK: - Pose detail pinned bar (F9)

/// The two pinned controls (the square Save and the primary Try action) share one height, taken from
/// the type size so they stay aligned and equal at every Dynamic Type size.
enum APBarMetrics {
    static func controlHeight(for size: DynamicTypeSize) -> CGFloat {
        size.isAccessibilitySize ? 72 : 52
    }
}

// MARK: - Add-pose request (Gallery `+`)

/// Whether a request from another tab may open Add pose: only when the feature is on and no route or
/// search is already presented (no duplicate presentation).
enum APAddPoseSignal {
    static func shouldOpen(canExtract: Bool, isRouteOpen: Bool, isSearchOpen: Bool) -> Bool {
        canExtract && !isRouteOpen && !isSearchOpen
    }
}

// MARK: - More menu rows (F8)

/// One row of the labelled More menu.
struct APMoreMenuRowSpec: Equatable {
    let title: String
    let systemImage: String
}

enum APMoreMenuSpec {
    /// Jobs carries the running-count badge (the only count the app still shows) and no subtitle;
    /// Saved has no subtitle; Settings is the gear row that opens the existing Settings screen.
    static func rows(showsSaved: Bool, showsSettings: Bool) -> [APMoreMenuRowSpec] {
        var rows = [APMoreMenuRowSpec(title: "Jobs", systemImage: "hourglass")]
        if showsSaved {
            rows.append(APMoreMenuRowSpec(title: "Saved", systemImage: "bookmark"))
        }
        if showsSettings {
            rows.append(APMoreMenuRowSpec(title: "Settings", systemImage: "gearshape"))
        }
        return rows
    }
}

// MARK: - Motion

/// Catalogue motion: a low-intensity card/grid animation that Reduce Motion turns off entirely.
enum APCatalogMotion {
    static let duration: Double = 0.2

    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: duration)
    }
}

// MARK: - Search chrome

/// Which chrome the Search results panel keeps mounted. The paging footer is mounted for **every**
/// panel, including an empty or no-match page: a filtered page can hold no match while the server
/// still has rows behind it, and a failed page must always offer its retry.
enum APSearchChrome {
    static func mountsPagingFooter(for presentation: APCatalogPresentation) -> Bool {
        switch presentation {
        case .loading, .failed, .empty, .noMatch, .grid:
            return true
        }
    }
}

// MARK: - Category filter

/// Multi-select category filter over the loaded catalogue. Client-side on purpose: the paged service
/// has no category parameter, and inventing one would change what a page means. The selection only
/// narrows the rows already fetched, and a page that arrives later is filtered the same way.
struct APCategoryFilter: Equatable {
    static let allTitle = "All"
    static let emptyTitle = "No poses match"
    static let recoveryTitle = "Show all"

    private(set) var selected: String?

    var isActive: Bool { selected != nil }
    var isEmpty: Bool { selected == nil }

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

    func isSelected(_ category: String) -> Bool { selected == category }

    mutating func toggle(_ category: String) {
        selected = selected == category ? nil : category
    }

    mutating func clear() { selected = nil }

    func matches(_ pose: NativePose) -> Bool {
        guard let selected else { return true }
        return selected == pose.category
    }

    func apply(to poses: [NativePose]) -> [NativePose] {
        guard selected != nil else { return poses }
        return poses.filter(matches)
    }

    /// Copy for the no-match panel: names the styles that are selected, so the panel explains itself.
    var message: String {
        guard let selected else { return "You don't have any poses in this category yet." }
        return "You don't have any \(selected) poses yet."
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
    static let loading = "Loading more poses…"
    static let failed = "Couldn't load more poses."
    static let retry = "Retry"
    static let end = "You've reached the end"

    /// The footer's trigger identity. It must change when an attempt *settles* (a page landed, failed or
    /// was discarded by the cursor guard) and must not change at request start — keying on `isLoading`
    /// cancelled the request that set it.
    static func triggerKey(
        phase: APPagingFooterPhase,
        nextOffset: Int,
        rowCount: Int,
        completedAttempts: Int
    ) -> String {
        "\(phase)-\(nextOffset)-\(rowCount)-\(completedAttempts)"
    }

    /// F6: infinite scroll. A list with rows behind it never waits for a tap — the footer's
    /// appearance fetches the next page (the model's own in-flight guard keeps it to one request).
    static func autoLoads(_ phase: APPagingFooterPhase) -> Bool {
        switch phase {
        case .loading, .loadMore: return true
        case .hidden, .failed, .end: return false
        }
    }

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

}
