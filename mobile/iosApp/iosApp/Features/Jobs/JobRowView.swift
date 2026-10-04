import Kingfisher
import SwiftUI

struct JobRowView: View {
    let row: JobRow
    var onAction: (JobRow) -> Void = { _ in }
    var onHide: ((JobRow) -> Void)? = nil

    private static let thumbnailSize: CGFloat = 56
    private static let cornerRadius: CGFloat = 12

    var body: some View {
        HStack(spacing: AIPoseSpacing.md) {
            thumbnailView

            VStack(alignment: .leading, spacing: 4) {
                Text(row.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AIPoseColor.foreground)
                    .lineLimit(1)

                statusBadge
            }

            Spacer(minLength: 8)

            actionButton
        }
        .padding(AIPoseSpacing.md)
        .background(AIPoseColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .stroke(AIPoseColor.foreground, lineWidth: 1.5)
        )
        .shadow(color: AIPoseColor.foreground, radius: 0, x: 2, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.name), \(row.statusLabel)\(row.action != .none ? ", \(row.action.rawValue)" : "")")
        .accessibilityAction(named: "Remove") {
            onHide?(row)
        }
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
        .background(AIPoseColor.surfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AIPoseColor.foreground, lineWidth: 1)
        )
    }

    private var thumbnailPlaceholder: some View {
        Image(systemName: "figure.stand")
            .font(.system(size: 24))
            .foregroundStyle(AIPoseColor.subtext)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 4) {
            switch row.status {
            case .queued:
                Text(row.statusLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AIPoseColor.subtext)
            case .processing:
                ProgressView()
                    .tint(AIPoseColor.foreground)
                    .scaleEffect(0.7)
                    .frame(width: 12, height: 12)
                Text(row.statusLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AIPoseColor.accentBlue)
            case .failed:
                Text(row.statusLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AIPoseColor.error)
            case .succeeded:
                Text(row.statusLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AIPoseColor.foreground)
            }
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
                    Text(row.action.rawValue)
                        .font(.system(size: 14, weight: .bold))
                        .padding(.horizontal, AIPoseSpacing.md)
                        .padding(.vertical, AIPoseSpacing.xs)
                }
                .buttonStyle(NeoButtonStyle(fill: AIPoseColor.surface))
                .accessibilityIdentifier("jobRow.retry.\(row.jobId)")
            }
        case .viewPose:
            Button {
                onAction(row)
            } label: {
                Text(row.action.rawValue)
                    .font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, AIPoseSpacing.md)
                    .padding(.vertical, AIPoseSpacing.xs)
            }
            .buttonStyle(NeoButtonStyle(fill: AIPoseColor.primary))
            .accessibilityIdentifier("jobRow.viewPose.\(row.jobId)")
        }
    }
}
