// Design-B catalogue components: the 44 pt header actions, the category and search-term chips, the
// raised pose card and the reflowing grid.

import Kingfisher
import SwiftUI
import UIKit

// MARK: - Header action button

/// `.nb-btn__compact-surface` replaced: a 44 × 44 glyph box. The fill and the pressed step come from
/// `APControlFillButtonStyle`, so a `Button` and a `NavigationLink` can look identical.
struct APHeaderActionGlyph: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .frame(width: AP.HitTarget.minimum, height: AP.HitTarget.minimum)
    }
}

/// The two visible header actions stay buttons; the third is the labelled More menu.
struct APHeaderActionButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            APHeaderActionGlyph(systemImage: systemImage)
        }
        .buttonStyle(APControlFillButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

/// A search-term chip (artboard `03-search-idle`: clock glyph + term, `controlFill`, radius 16).
struct APSearchTermChip: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AP.Space.space8) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .regular))
                    .accessibilityHidden(true)
                Text(title)
                    .font(AP.Font.supporting)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AP.Space.space16)
            .frame(minHeight: AP.HitTarget.minimum)
        }
        .buttonStyle(APSearchTermChipStyle())
    }
}

private struct APSearchTermChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        APSearchTermChipBody(configuration: configuration)
    }
}

private struct APSearchTermChipBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .foregroundStyle(AP.Color.primaryText)
            .background(
                RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                    .fill(configuration.isPressed ? AP.Color.controlFillPressed : AP.Color.controlFill)
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? AP.Press.scale : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: AP.Press.duration),
                value: configuration.isPressed
            )
    }
}

/// `controlFill` → `controlFillPressed`, scale 0.97, Reduce Motion keeps the fill step only.
struct APControlFillButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = AP.Radius.radius16
    var foreground: SwiftUI.Color = AP.Color.primaryText

    func makeBody(configuration: Configuration) -> some View {
        APControlFillButtonBody(configuration: configuration, cornerRadius: cornerRadius, foreground: foreground)
    }
}

private struct APControlFillButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let cornerRadius: CGFloat
    let foreground: SwiftUI.Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .foregroundStyle(isEnabled ? foreground : AP.Color.disabled)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? AP.Press.scale : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: AP.Press.duration),
                value: configuration.isPressed
            )
    }

    private var fill: SwiftUI.Color {
        guard isEnabled else { return AP.Color.controlFill }
        return configuration.isPressed ? AP.Color.controlFillPressed : AP.Color.controlFill
    }
}

// MARK: - Category chip

/// `.nb-search-filter` replaced: radius 16, `controlFill` / `selectedBackground` fills, a check glyph
/// on the selected chip (never colour alone), 44 pt minimum height and a wrapping label.
struct APCategoryChip: View {
    let title: String
    var isSelected: Bool
    /// Accessibility sizes stack the chips full width, one per row (artboard `…-loaded-ax3`).
    var fillsWidth: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AP.Space.space8) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(AP.Font.supporting)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AP.Space.space16)
            .frame(
                maxWidth: fillsWidth ? .infinity : nil,
                minHeight: AP.HitTarget.minimum,
                alignment: fillsWidth ? .leading : .center
            )
        }
        .buttonStyle(APCategoryChipStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct APCategoryChipStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        APCategoryChipBody(configuration: configuration, isSelected: isSelected)
    }
}

private struct APCategoryChipBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .foregroundStyle(isSelected ? AP.Color.selectedForeground : AP.Color.primaryText)
            .background(
                RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                    .fill(fill)
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? AP.Press.scale : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: AP.Press.duration),
                value: configuration.isPressed
            )
    }

    private var fill: SwiftUI.Color {
        if isSelected {
            // The selected fill keeps its identity while pressed; the check glyph and trait carry state.
            return AP.Color.selectedBackground
        }
        return configuration.isPressed ? AP.Color.controlFillPressed : AP.Color.controlFill
    }
}

/// The filter row: one horizontally scrolling line at the default sizes, stacked full-width rows at
/// the Accessibility sizes. "All" clears the selection and carries the check glyph when nothing else is.
struct APCategoryFilterBar: View {
    let categories: [String]
    let filter: APCategoryFilter
    let onToggle: (String) -> Void
    let onClear: () -> Void
    var identifierPrefix: String = "poses.category"

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AP.Space.space8) {
                allChip(fillsWidth: true)
                ForEach(categories, id: \.self) { category in
                    chip(for: category, fillsWidth: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AP.Space.space8) {
                    allChip(fillsWidth: false)
                    ForEach(categories, id: \.self) { category in
                        chip(for: category, fillsWidth: false)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func allChip(fillsWidth: Bool) -> some View {
        APCategoryChip(
            title: APCategoryFilter.allTitle,
            isSelected: filter.isEmpty,
            fillsWidth: fillsWidth,
            action: onClear
        )
        .accessibilityIdentifier("\(identifierPrefix).all")
    }

    private func chip(for category: String, fillsWidth: Bool) -> some View {
        APCategoryChip(
            title: category,
            isSelected: filter.isSelected(category),
            fillsWidth: fillsWidth,
            action: { onToggle(category) }
        )
        .accessibilityIdentifier("\(identifierPrefix).\(category.lowercased())")
    }
}

// MARK: - Pose card

/// `.nb-card--pose-grid` replaced: a raised `surface` card (E1 + dark `cardStroke`), radius 16, no
/// border, with the name and category inside the card (artboard `02-poses-home-loaded`).
struct APPoseCard: View {
    let pose: NativePose
    var aspectRatio: CGFloat = 1
    var zoomNamespace: Namespace.ID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            artwork
                .frame(maxWidth: .infinity)
                .aspectRatio(aspectRatio, contentMode: .fit)
                .clipped()
                .overlay(alignment: .topTrailing) { savedBadge }
            VStack(alignment: .leading, spacing: AP.Space.space4) {
                Text(pose.name)
                    .font(AP.Font.heading)
                    .foregroundStyle(AP.Color.primaryText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if !pose.category.isEmpty {
                    Text(pose.category)
                        .font(AP.Font.supporting)
                        .foregroundStyle(AP.Color.secondaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(AP.Space.space12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AP.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous))
        // The zoom source clips its own copy of the card; the E1 shadow has to sit outside that clip
        // or the card loses it at rest (token values unchanged: 8% black, 0 1 2 + 0 4 12).
        .zoomTransitionSource(id: pose.id, in: zoomNamespace, cornerRadius: AP.Radius.radius16)
        .apElevation(.e1, cornerRadius: AP.Radius.radius16)
        .animation(APCatalogMotion.animation(reduceMotion: reduceMotion), value: aspectRatio)
    }

    /// Same two-tier Kingfisher cache as the legacy card: a grid re-render must not re-decode.
    private var artwork: some View {
        KFImage(pose.imageURL)
            .setProcessor(AppImage.downsample(points: APGridLayout.artworkPoints(columns: 2), contentMode: .fit))
            .onSuccess { result in
                PoseAspectRatioCache.shared.updateRatio(
                    width: result.image.size.width,
                    height: result.image.size.height,
                    for: pose.id
                )
            }
            .placeholder {
                Image(systemName: "figure.stand")
                    .font(.system(size: 44))
                    .foregroundStyle(AP.Color.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .resizable()
            .scaledToFill()
            .clipped()
    }

    @ViewBuilder private var savedBadge: some View {
        if pose.isSaved {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AP.Color.selectedForeground)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: AP.Radius.radius8, style: .continuous)
                        .fill(AP.Color.selectedBackground)
                )
                .padding(AP.Space.space8)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Pose grid

/// The catalogue grid: masonry at 2 columns, a single column at the Accessibility sizes. Same paging
/// trigger and accessibility identifiers as `PoseGrid`.
@MainActor
struct APPoseGrid: View {
    let poses: [NativePose]
    @ObservedObject var model: PosesViewModel
    var onTryPose: (CameraPoseRequest) -> Void = { _ in }
    var onNearEnd: (() -> Void)?
    @ObservedObject private var aspectRatioCache: PoseAspectRatioCache
    @State private var columnByPoseID: [String: Int] = [:]
    @Namespace private var zoomNamespace

    private struct Item: Identifiable {
        let index: Int
        let pose: NativePose
        var id: String { pose.id }
    }

    init(
        poses: [NativePose],
        model: PosesViewModel,
        onTryPose: @escaping (CameraPoseRequest) -> Void = { _ in },
        onNearEnd: (() -> Void)? = nil
    ) {
        self.poses = poses
        _model = ObservedObject(wrappedValue: model)
        self.onTryPose = onTryPose
        self.onNearEnd = onNearEnd
        let cache = PoseAspectRatioCache.shared
        _aspectRatioCache = ObservedObject(wrappedValue: cache)
        _columnByPoseID = State(initialValue: Self.assignments(for: poses, using: cache, columns: 2))
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var columns: Int { APGridLayout.columns(for: dynamicTypeSize) }

    private var itemsByColumn: [[Item]] {
        var buckets = Array(repeating: [Item](), count: columns)
        for (index, pose) in poses.enumerated() {
            let column = columnByPoseID[pose.id] ?? (index % columns)
            buckets[min(max(column, 0), columns - 1)].append(Item(index: index, pose: pose))
        }
        return buckets
    }

    var body: some View {
        let buckets = itemsByColumn
        return HStack(alignment: .top, spacing: APGridLayout.columnSpacing) {
            ForEach(0..<columns, id: \.self) { columnIndex in
                LazyVStack(alignment: .leading, spacing: APGridLayout.rowSpacing) {
                    ForEach(buckets[columnIndex]) { item in
                        NavigationLink(
                            destination: PoseDetailScreen(pose: item.pose, model: model, onTryPose: onTryPose)
                                .zoomTransition(sourceID: item.pose.id, in: zoomNamespace)
                        ) {
                            APPoseCard(
                                pose: item.pose,
                                aspectRatio: aspectRatioCache.ratio(for: item.pose.id),
                                zoomNamespace: zoomNamespace
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            item.index == 0 ? "poses.first-card" : "poses.card.\(item.pose.id)"
                        )
                        .accessibilitySortPriority(Double(poses.count - item.index))
                        .onAppear {
                            guard item.index >= poses.count - 4 else { return }
                            onNearEnd?()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear(perform: rebuildAssignments)
        .onChange(of: poses.map(\.id)) { _ in rebuildAssignments() }
        .onChange(of: dynamicTypeSize) { _ in rebuildAssignments() }
        .onReceive(
            aspectRatioCache.$ratios
                .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
                .removeDuplicates()
        ) { _ in
            rebuildAssignments()
        }
    }

    private static func assignments(
        for poses: [NativePose],
        using cache: PoseAspectRatioCache,
        columns: Int
    ) -> [String: Int] {
        let result = APGridLayout.columnAssignments(
            for: poses.map { cache.ratio(for: $0.id) },
            columnWidth: APGridLayout.screenColumnWidth(columns: columns),
            columns: columns
        )
        return Dictionary(uniqueKeysWithValues: zip(poses.map(\.id), result))
    }

    private func rebuildAssignments() {
        let updated = Self.assignments(for: poses, using: aspectRatioCache, columns: columns)
        guard updated != columnByPoseID else { return }
        withAnimation(APCatalogMotion.animation(reduceMotion: reduceMotion)) {
            columnByPoseID = updated
        }
    }
}

// MARK: - Search state panel

/// The non-grid Search results panels (`03-search-loading/error/no-results`), extracted from
/// `SearchScreen` so a probe can render exactly what the screen shows — including the paging footer,
/// which must survive an empty page (a filtered page can hold no match while more rows exist).
struct APSearchStatePanel: View {
    @ObservedObject var model: PosesViewModel
    let presentation: APCatalogPresentation
    var failureTitle: String = ""
    var failureMessage: String = ""
    var emptyTitle: String = ""
    var emptyMessage: String = ""
    var emptyActionTitle: String?
    var onEmptyAction: () -> Void = {}
    var onRetry: () -> Void = {}
    var emptyIdentifier: String?
    var retryIdentifier: String?

    @ViewBuilder var body: some View {
        switch presentation {
        case .loading:
            APLoadingStateView(label: "Searching")
                .padding(.horizontal, AP.Space.space16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .failed:
            VStack(spacing: 0) {
                APErrorStateView(
                    title: failureTitle,
                    message: failureMessage,
                    retry: onRetry,
                    style: .plain
                )
                .apIdentifier(retryIdentifier)
                searchFooter
            }
        case .empty, .noMatch:
            VStack(spacing: 0) {
                APEmptyStateView(
                    title: emptyTitle,
                    message: emptyMessage,
                    actionTitle: emptyActionTitle,
                    action: onEmptyAction,
                    style: .plain
                )
                .apIdentifier(emptyIdentifier)
                searchFooter
            }
        case .grid:
            // The screen draws the grid branch itself.
            EmptyView()
        }
    }

    private var searchFooter: some View {
        APPagingFooter(model: model, bottomInset: APGridLayout.rowSpacing)
    }
}

extension View {
    /// Applies an accessibility identifier only when the caller supplied one.
    @ViewBuilder
    func apIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}
