import Kingfisher
import SwiftUI

/// Where a row sits inside the grouped list card. Boards `09-board01/03/06` group a segment's rows in
/// ONE `surface` card: only the outer corners are rounded, and every row but the last draws the
/// hairline that separates it from the next one.
enum JobRowGroupPosition: Equatable {
    case single
    case first
    case middle
    case last

    static func position(at index: Int, count: Int) -> JobRowGroupPosition {
        if count <= 1 { return .single }
        if index == 0 { return .first }
        if index == count - 1 { return .last }
        return .middle
    }

    var topRadius: CGFloat { self == .single || self == .first ? AP.Radius.radius16 : 0 }
    var bottomRadius: CGFloat { self == .single || self == .last ? AP.Radius.radius16 : 0 }
    var drawsSeparator: Bool { self != .single && self != .last }
}

/// The grouped card's outline: radius 16 on the card's outer edge, square where the next row continues.
struct JobGroupCardShape: Shape {
    var topRadius: CGFloat = AP.Radius.radius16
    var bottomRadius: CGFloat = AP.Radius.radius16

    func path(in rect: CGRect) -> Path {
        let top = max(0, min(topRadius, rect.height / 2))
        let bottom = max(0, min(bottomRadius, rect.height / 2))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + top))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + top),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - bottom, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - bottom),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// One extraction job. Every state carries three signals — colour, glyph and words — so the row never
/// relies on colour alone (boards `09-board06`): `Queued` (hourglass), `Processing` (sparkles plus the
/// striped indeterminate bar), `Done · added to Poses` (checkmark, chevron) and
/// `Failed · <server reason>` (warning triangle, Retry).
struct JobRowView: View {
    let row: JobRow
    /// The poll is failing right now: a queued row says so instead of pretending it is waiting on a
    /// worker (`Queued · waiting for connection`, board `09-board06`).
    var waitingForConnection: Bool = false
    var groupPosition: JobRowGroupPosition = .single
    var onAction: (JobRow) -> Void = { _ in }
    var onHide: ((JobRow) -> Void)? = nil

    private static let thumbnailSize: CGFloat = 56

    var body: some View {
        HStack(alignment: .top, spacing: AP.Space.space12) {
            thumbnailView
                // Decorative: the summary element below already speaks the name and the state.
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AP.Space.space4) {
                Text(row.name)
                    .font(AP.Font.heading)
                    .foregroundStyle(AP.Color.primaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                statusLine

                if row.status == .processing {
                    JobIndeterminateBar()
                        .padding(.top, AP.Space.space4)
                        .padding(.trailing, AP.Space.space8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Only the text group is combined. `children: .combine` on the row itself swallowed the
            // action button, so `jobRow.retry.<id>` / `jobRow.viewPose.<id>` never reached the
            // accessibility tree and no UI test could tap them.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Self.accessibilitySummary(for: row, waitingForConnection: waitingForConnection))
            .accessibilityIdentifier(Self.nameIdentifier(jobId: row.jobId))
            .accessibilityAction(named: "Hide") {
                onHide?(row)
            }

            actionButton
        }
        .padding(.horizontal, AP.Space.space16)
        .padding(.vertical, AP.Space.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            JobGroupCardShape(topRadius: groupPosition.topRadius, bottomRadius: groupPosition.bottomRadius)
                .fill(AP.Color.surface)
        )
        .overlay(alignment: .bottom) {
            if groupPosition.drawsSeparator {
                Rectangle()
                    .fill(AP.Color.separator)
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
        }
        // A container, not one combined element: the summary text and the action button must stay
        // separate accessibility elements.
        .accessibilityElement(children: .contain)
    }

    /// The one sentence assistive tech reads for the row.
    static func accessibilitySummary(for row: JobRow, waitingForConnection: Bool = false) -> String {
        let status = statusText(for: row, waitingForConnection: waitingForConnection)
        return "\(row.name), \(status)\(row.action != .none ? ", \(row.action.rawValue)" : "")"
    }

    /// The status line a sighted user reads and VoiceOver speaks, without inventing a percentage: the
    /// server reports the stage only.
    static func statusText(for row: JobRow, waitingForConnection: Bool = false) -> String {
        guard waitingForConnection, row.status == .queued else { return row.statusText }
        return JobsCopy.statusLine(label: JobsCopy.queued, detail: JobsCopy.waitingForConnection)
    }

    /// Identifier carried by the retry button. It sits on the button inside the row's `.contain`
    /// element, so a UI test reaches it without matching the row summary.
    static func retryIdentifier(jobId: String) -> String {
        "jobRow.retry.\(jobId)"
    }

    /// Identifier carried by the view-pose button, with the same containment contract as
    /// `retryIdentifier(jobId:)`.
    static func viewPoseIdentifier(jobId: String) -> String {
        "jobRow.viewPose.\(jobId)"
    }

    /// The row summary element also answers to its own id, so a test can assert on the name without
    /// matching a possibly truncated label (TC-JOB-010).
    static func nameIdentifier(jobId: String) -> String {
        "jobRow.name.\(jobId)"
    }

    @ViewBuilder
    private var thumbnailView: some View {
        Group {
            if let urlString = row.thumbnailUrl,
               let url = CommunityPoseMapper.resolveURL(urlString, baseURL: AppConfig.shared.SERVER_BASE_URL) {
                KFImage(url)
                    .placeholder {
                        thumbnailPlaceholder
                    }
                    .resizable()
                    .scaledToFill()
            } else {
                thumbnailPlaceholder
            }
        }
        .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
        .background(AP.Color.controlFill)
        .clipShape(RoundedRectangle(cornerRadius: AP.Radius.radius8, style: .continuous))
    }

    private var thumbnailPlaceholder: some View {
        Image(systemName: "figure.stand")
            .font(.system(size: 22, weight: .regular))
            .foregroundStyle(AP.Color.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: AP.Space.space8) {
            Image(systemName: statusGlyph)
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
            Text(Self.statusText(for: row, waitingForConnection: waitingForConnection))
                .font(AP.Font.supporting)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(statusColor)
    }

    private var statusGlyph: String {
        switch row.status {
        case .queued:
            return waitingForConnection ? "wifi.slash" : "hourglass"
        case .processing:
            return "sparkles"
        case .failed:
            return "exclamationmark.triangle"
        case .succeeded:
            return "checkmark"
        }
    }

    private var statusColor: SwiftUI.Color {
        switch row.status {
        case .queued, .processing:
            return AP.Color.secondaryText
        case .failed:
            return AP.Color.error
        case .succeeded:
            return AP.Color.success
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch row.action {
        case .none:
            EmptyView()
        case .retry:
            if AppConfig.canExtractPose(isEnabled: AppConfig.shared.isExtractPoseEnabled) {
                Button {
                    onAction(row)
                } label: {
                    Text(JobRowAction.retry.rawValue)
                        .font(AP.Font.heading)
                        .foregroundStyle(AP.Color.accentText)
                        .apMinimumHitTarget()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(Self.retryIdentifier(jobId: row.jobId))
            }
        case .viewPose:
            Button {
                onAction(row)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AP.Color.secondaryText)
                    .apMinimumHitTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(JobRowAction.viewPose.rawValue)
            .accessibilityIdentifier(Self.viewPoseIdentifier(jobId: row.jobId))
        }
    }
}

/// The in-progress bar from boards `09-board01/06`: diagonal stripes marching across a short band, no
/// fill ratio. The server reports a stage, never a percentage, so this bar is indeterminate by
/// contract; Reduce Motion freezes the stripes instead of dropping them.
struct JobIndeterminateBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let height: CGFloat = 12
    static let stripeWidth: CGFloat = 9
    static let stripeGap: CGFloat = 6
    /// One full cycle of stripe + gap: the marching distance that loops seamlessly.
    static var period: CGFloat { stripeWidth + stripeGap }
    static let duration: Double = 0.9

    @State private var phase: CGFloat = 0

    var body: some View {
        Color.clear
            .frame(height: Self.height)
            .overlay(alignment: .leading) {
                HStack(spacing: Self.stripeGap) {
                    ForEach(0..<40, id: \.self) { _ in
                        JobStripe()
                            .fill(AP.Color.selectedForeground)
                            .frame(width: Self.stripeWidth, height: Self.height)
                    }
                }
                .fixedSize()
                .offset(x: phase)
            }
            .clipShape(RoundedRectangle(cornerRadius: Self.height / 2, style: .continuous))
            .accessibilityHidden(true)
            .onAppear(perform: startMarching)
    }

    private func startMarching() {
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: Self.duration).repeatForever(autoreverses: false)) {
            phase = Self.period
        }
    }
}

/// One diagonal band: a parallelogram leaning right, so a row of them reads as hatching.
private struct JobStripe: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width / 2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width / 2, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
