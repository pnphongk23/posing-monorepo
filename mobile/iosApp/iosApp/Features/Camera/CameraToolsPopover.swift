import SwiftUI

/// The camera tools popover: four one-line rows anchored under the tools control — the camera's whole settings
/// surface, kept in its own file because it is a surface, not a corner of the screen.
///
/// Every row applies the moment it changes and persists immediately; the popover is dismissed by tapping
/// outside or with VoiceOver's escape, so there is no Done. The guide's own controls (opacity, line colour,
/// scale, mirror) live in the guide-adjust sheet, not here.
enum CameraToolsLayout {
    /// The rows, top to bottom. Exactly four, one line each.
    enum Row: String, CaseIterable {
        case flash, grid, timer, ratio

        var title: String {
            switch self {
            case .flash: return "Flash"
            case .grid: return "Grid"
            case .timer: return "Timer"
            case .ratio: return "Ratio"
            }
        }

        var symbolName: String {
            switch self {
            case .flash: return "bolt.fill"
            case .grid: return "squares.below.rectangle"
            case .timer: return "timer"
            case .ratio: return "rectangle.portrait"
            }
        }

        var accessibilityIdentifier: String { "camera.tools.\(rawValue)" }
    }

    static let rows: [Row] = Row.allCases

    /// The chips the board draws: a 30 pt pill with 14 pt type, inside a 44 pt row (which is the tap target).
    /// Measured on `05-camera-tools-sheet.png` at the 393 pt reference.
    static let chipHeight: CGFloat = 30
    static let chipFontSize: CGFloat = 14
    static let chipHitTarget: CGFloat = AP.HitTarget.minimum
    static let chipGap: CGFloat = 6
    static let chipHorizontalPadding: CGFloat = 6

    /// The artboard's card: 232 pt wide, its right edge on the tools control's right edge.
    static let width: CGFloat = 232
    static let rowHeight: CGFloat = AP.HitTarget.minimum
    static let caret = CGSize(width: 14, height: 8)

    /// The caret points up at the tools control, so its centre is half a control in from the card's right edge.
    static func caretCenterX(cardWidth: CGFloat = width) -> CGFloat {
        cardWidth - AP.HitTarget.minimum / 2
    }

    /// The card's top edge: a short gap under the top control row (the row's measured height already includes
    /// the safe-area top). The caret's tip sits inside that gap, pointing at the control.
    static func cardTop(belowTopBar topBarHeight: CGFloat) -> CGFloat {
        topBarHeight + AP.Space.space4
    }

    /// The whole thing: the caret plus four rows and their hairlines.
    static var height: CGFloat {
        caret.height + rowHeight * CGFloat(rows.count) + CGFloat(rows.count - 1)
    }

    /// Ids this popover used to expose and no longer does. The guide's controls moved to the guide-adjust sheet
    /// (with new handles there), and the Flash row became three chips instead of a cycling value.
    static let retiredIdentifiers = [
        "camera.tools.done",
        "camera.tools.poseGuide",
        "camera.tools.mirror",
        "camera.tools.mirror.switch",
        "camera.tools.opacity",
        "camera.tools.scale",
        "camera.tools.scale.reset",
        "camera.tools.lineColor.black",
        "camera.tools.lineColor.white",
    ]

    /// The ids the four rows expose. A change lands on the model directly (no commit step), so a setting is
    /// persisted while the popover is still open.
    static var controlIdentifiers: [String] { rows.map(\.accessibilityIdentifier) }
}

/// The camera's settings surface: a small popover under the tools control with a caret pointing up at it, four
/// one-line rows of 44 pt, `surface` fill and the elevation's card stroke — no scrim, no handle, no Done.
struct CameraToolsPopup: View {
    let flashSetting: CameraFlashSetting
    let isGridVisible: Bool
    let controlsEnabled: Bool
    let timerSetting: CameraTimerSetting
    let aspectRatio: CameraAspectRatio
    let onFlashChange: (CameraFlashSetting) -> Void
    let onGridToggle: () -> Void
    let onTimerChange: (CameraTimerSetting) -> Void
    let onAspectRatioChange: (CameraAspectRatio) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(CameraToolsLayout.rows.enumerated()), id: \.element) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(AP.Color.separator)
                        .frame(height: 1)
                }
                self.row(row)
            }
        }
        .padding(.top, CameraToolsLayout.caret.height)
        .frame(width: CameraToolsLayout.width)
        .background(
            CameraToolsCardShape(caretCenterX: CameraToolsLayout.caretCenterX())
                .fill(AP.Color.surface)
        )
        .modifier(
            APElevationModifier(
                level: .e1,
                shape: CameraToolsCardShape(caretCenterX: CameraToolsLayout.caretCenterX())
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera.tools.popover")
        // VoiceOver's local Back (two-finger Z scrub) — the native equivalent of Escape.
        .accessibilityAction(.escape) { onDismiss() }
    }

    @ViewBuilder
    private func row(_ row: CameraToolsLayout.Row) -> some View {
        HStack(spacing: AP.Space.space8) {
            Image(systemName: row.symbolName)
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.primaryText)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(row.title)
                .font(.system(size: 15))
                .foregroundStyle(AP.Color.primaryText)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: AP.Space.space4)
            control(for: row)
        }
        .padding(.horizontal, AP.Space.space8)
        .frame(height: CameraToolsLayout.rowHeight)
        .opacity(controlsEnabled ? 1 : 0.45)
        .accessibilityIdentifier(row.accessibilityIdentifier)
    }

    @ViewBuilder
    private func control(for row: CameraToolsLayout.Row) -> some View {
        switch row {
        case .flash:
            HStack(spacing: CameraToolsLayout.chipGap) {
                ForEach(CameraFlashSetting.toolsChoices, id: \.self) { setting in
                    chip(setting.toolsDisplayName, isSelected: flashSetting == setting,
                         identifier: "camera.tools.flash.\(setting.toolsSlug)",
                         accessibilityLabel: "Flash \(setting.toolsDisplayName)") {
                        onFlashChange(setting)
                    }
                }
            }
        case .grid:
            Toggle("", isOn: Binding(get: { isGridVisible }, set: { _ in onGridToggle() }))
                .labelsHidden()
                .tint(AP.Color.accent)
                .disabled(!controlsEnabled)
                .accessibilityLabel("Show camera grid")
                .accessibilityValue(isGridVisible ? "On" : "Off")
                .accessibilityIdentifier("camera.tools.grid")
        case .timer:
            HStack(spacing: CameraToolsLayout.chipGap) {
                ForEach(CameraTimerSetting.allCases) { setting in
                    chip(setting.rawValue, isSelected: timerSetting == setting,
                         identifier: setting.accessibilityIdentifier,
                         accessibilityLabel: "Timer \(setting.rawValue)") {
                        onTimerChange(setting)
                    }
                }
            }
        case .ratio:
            HStack(spacing: CameraToolsLayout.chipGap) {
                ForEach(CameraAspectRatio.allCases) { ratio in
                    chip(ratio.rawValue, isSelected: aspectRatio == ratio,
                         identifier: ratio.accessibilityIdentifier,
                         accessibilityLabel: "Ratio \(ratio.rawValue)") {
                        onAspectRatioChange(ratio)
                    }
                }
            }
        }
    }

    /// One option chip: the choice's own word, a check glyph when it is the current one, and the selected fill
    /// behind it — so the state is never colour alone.
    private func chip(
        _ title: String,
        isSelected: Bool,
        identifier: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 2) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.system(size: CameraToolsLayout.chipFontSize, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(isSelected ? AP.Color.selectedForeground : AP.Color.primaryText)
            .padding(.horizontal, CameraToolsLayout.chipHorizontalPadding)
            .frame(height: CameraToolsLayout.chipHeight)
            .background(
                Capsule().fill(isSelected ? AP.Color.selectedBackground : AP.Color.controlFill)
            )
        }
        .buttonStyle(.plain)
        // The pill draws 30 pt tall; the finger gets the board's 44 pt row.
        .apMinimumHitTarget()
        .disabled(!controlsEnabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(identifier)
    }
}

/// The popover's own silhouette: a rounded card with a caret rising from its top edge at `caretCenterX`.
struct CameraToolsCardShape: InsettableShape {
    let caretCenterX: CGFloat
    var inset: CGFloat = 0
    let cornerRadius: CGFloat = AP.Radius.radius16

    func path(in rect: CGRect) -> Path {
        let card = CGRect(
            x: rect.minX + inset,
            y: rect.minY + CameraToolsLayout.caret.height + inset,
            width: rect.width - inset * 2,
            height: rect.height - CameraToolsLayout.caret.height - inset * 2
        )
        var path = Path(roundedRect: card, cornerRadius: cornerRadius, style: .continuous)

        let caretHalf = CameraToolsLayout.caret.width / 2
        let center = card.minX + min(max(caretCenterX, cornerRadius + caretHalf), card.width - cornerRadius - caretHalf)
        var caret = Path()
        caret.move(to: CGPoint(x: center - caretHalf, y: card.minY))
        caret.addLine(to: CGPoint(x: center, y: rect.minY + inset))
        caret.addLine(to: CGPoint(x: center + caretHalf, y: card.minY))
        caret.closeSubpath()
        path.addPath(caret)
        return path
    }

    func inset(by amount: CGFloat) -> CameraToolsCardShape {
        CameraToolsCardShape(caretCenterX: caretCenterX, inset: inset + amount)
    }
}
