// Design-B catalogue loading and paging chrome: the flat skeleton grid and the paged footer.

import SwiftUI

// MARK: - Loading skeleton

/// Flat `controlFill` skeletons laid out like the grid they replace (artboard `02-poses-home-loading`):
/// chip bars, then card blocks with a title bar and a category bar.
@MainActor
struct APPoseGridSkeleton: View {
    var rows: Int = 3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: AP.Space.space16) {
            HStack(spacing: AP.Space.space8) {
                APSkeletonBar(width: 96, height: 44, opacity: opacity)
                APSkeletonBar(width: 140, height: 44, opacity: opacity)
            }
            let columns = APGridLayout.columns(for: dynamicTypeSize)
            HStack(alignment: .top, spacing: APGridLayout.columnSpacing) {
                ForEach(0..<columns, id: \.self) { _ in
                    VStack(spacing: APGridLayout.rowSpacing) {
                        ForEach(0..<rows, id: \.self) { _ in
                            cardSkeleton
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading poses")
        .onAppear(perform: startPulse)
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var opacity: Double {
        APSkeleton.opacity(isPulsing: isPulsing, reduceMotion: reduceMotion)
    }

    private var cardSkeleton: some View {
        VStack(alignment: .leading, spacing: AP.Space.space8) {
            APSkeletonBar(height: 180, opacity: opacity)
                .clipShape(RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous))
            APSkeletonBar(width: 120, opacity: opacity)
            APSkeletonBar(width: 80, height: 10, opacity: opacity)
        }
    }

    private func startPulse() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: APSkeleton.pulseDuration).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }
}

// MARK: - Paging footer

/// Paged-list footer: the auto-fetch indicator, the explicit "Load more" step, the failed row and the
/// end-of-list line. Renders nothing when there is nothing to say, so a caller can mount it always.
struct APPagingFooter: View {
    @ObservedObject var model: PosesViewModel
    /// Bottom clearance (dock overlay) when this footer is the last thing inside a scroll view.
    var bottomInset: CGFloat = APGridLayout.dockClearance

    var body: some View {
        let phase = APPagingFooterRule.phase(
            error: model.paging.error,
            hasMore: model.paging.hasMore,
            remainingAutoFetches: model.paging.remainingAutoFetches,
            hasRows: hasRows
        )
        VStack(spacing: AP.Space.space8) {
            switch phase {
            case .hidden:
                EmptyView()
            case .loading:
                // F6: reaching the end auto-loads; the footer is only a small spinner.
                HStack(spacing: AP.Space.space8) {
                    Image(systemName: "circle.dashed")
                        .font(AP.Font.supporting)
                        .foregroundStyle(AP.Color.secondaryText)
                        .accessibilityHidden(true)
                    Text(APPagingFooterRule.loading)
                        .font(AP.Font.supporting)
                        .foregroundStyle(AP.Color.secondaryText)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(APPagingFooterRule.loading)
                // Fires once per appearance; the model ignores it while a page is in flight.
                .onAppear { Task { await model.loadMore() } }
            case .loadMore:
                // No "Load more" button any more: the same appearance auto-fetches the next page.
                HStack(spacing: AP.Space.space8) {
                    Image(systemName: "circle.dashed")
                        .font(AP.Font.supporting)
                        .foregroundStyle(AP.Color.secondaryText)
                        .accessibilityHidden(true)
                    Text(APPagingFooterRule.loading)
                        .font(AP.Font.supporting)
                        .foregroundStyle(AP.Color.secondaryText)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(APPagingFooterRule.loading)
                .onAppear { Task { await model.loadMoreResults() } }
            case .failed:
                Button {
                    Task { await model.loadMoreResults() }
                } label: {
                    HStack(spacing: AP.Space.space8) {
                        Image(systemName: APStateTone.error.glyph)
                            .font(AP.Font.supporting)
                            .foregroundStyle(AP.Color.error)
                            .accessibilityHidden(true)
                        Text(APPagingFooterRule.failed)
                            .font(AP.Font.supporting)
                            .foregroundStyle(AP.Color.primaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: AP.Space.space8)
                        Text(APPagingFooterRule.retry)
                            .font(AP.Font.supporting.weight(.semibold))
                            .foregroundStyle(AP.Color.accentText)
                    }
                    .padding(AP.Space.space12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                            .fill(AP.Color.errorSurface)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("poses.loadMore.retry")
                .accessibilityHint(model.paging.error ?? "")
            case .end:
                Text(APPagingFooterRule.end)
                    .font(AP.Font.caption)
                    .foregroundStyle(AP.Color.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AP.Space.space16)
        .padding(.top, AP.Space.space8)
        .padding(.bottom, bottomInset)
    }

    private var hasRows: Bool {
        !model.state.rows.isEmpty
    }
}

extension Loadable where Value == [NativePose] {
    /// Rows currently held by the state, or none.
    var rows: [NativePose] {
        if case .loaded(let poses) = self { return poses }
        return []
    }
}
