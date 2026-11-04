import SwiftUI

/// The pose reference's stroke colour, as the guide-adjust sheet's swatches offer it.
enum GuideLineColor: String, CaseIterable, Identifiable, Sendable {
    case pink, black, yellow, green

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// The stroke itself. Pink is the brand accent, black is ink, and the other two are the palette's
    /// success/warning fills — all four read on both a bright sky and a dark interior.
    var color: Color {
        switch self {
        case .pink: return AP.Color.accent
        case .black: return AP.Color.onAccent
        case .yellow: return AP.Color.warning
        case .green: return AP.Color.success
        }
    }

    /// The swatch's fill, so a light colour still has an edge.
    var swatchColor: Color { color }

    var accessibilityIdentifier: String { "camera.guideAdjust.lineColor.\(rawValue)" }

    /// A stored row from before the palette existed says `white`; the sheet's default is pink, which is what
    /// that row meant (the reference's light stroke).
    static func stored(_ raw: String?) -> GuideLineColor? {
        guard let raw else { return nil }
        if raw == "white" { return .pink }
        return GuideLineColor(rawValue: raw)
    }
}

/// The guide-adjust sheet: everything about the pose reference itself — how strong it is, what colour it is
/// drawn in, how big it is and whether it is mirrored — with one Done. The camera behind stays live, so the
/// change is visible while it is made.
struct CameraGuideAdjustSheet: View {
    let opacity: Double
    let lineColor: GuideLineColor
    let scale: CGFloat
    let isFlipped: Bool
    let isEnabled: Bool
    let onOpacityChange: (Double) -> Void
    let onLineColorChange: (GuideLineColor) -> Void
    let onScaleChange: (CGFloat) -> Void
    let onFlip: () -> Void
    let onDone: () -> Void

    /// The sheet's handles. `camera.guideAdjust` is the sheet itself (a container), the rest are its controls.
    enum Layout {
        static let sheetIdentifier = "camera.guideAdjust"
        static let opacityIdentifier = "camera.guideAdjust.opacity"
        static let scaleIdentifier = "camera.guideAdjust.scale"
        static let flipIdentifier = "camera.guideAdjust.flip"
        static let doneIdentifier = "camera.guideAdjust.done"
        static let height: CGFloat = 340
    }

    var body: some View {
        VStack(spacing: 0) {
            handle
            header
            opacityRow
            lineColorRow
            scaleRow
            flipRow
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AP.Space.space16)
        .padding(.bottom, AP.Space.space16)
        .frame(maxWidth: .infinity)
        .frame(height: Layout.height, alignment: .top)
        .background(
            RoundedTopShape(radius: AP.Radius.radius24)
                .fill(AP.Color.surface)
        )
        .clipShape(RoundedTopShape(radius: AP.Radius.radius24))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier(Layout.sheetIdentifier)
        .accessibilityAction(.escape) { onDone() }
    }

    private var handle: some View {
        Capsule()
            .fill(AP.Color.separator)
            .frame(width: AP.Space.space32, height: AP.Space.space4)
            .padding(.top, AP.Space.space8)
            .padding(.bottom, AP.Space.space12)
            .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: AP.Space.space8) {
            Text("Adjust guide")
                .font(AP.Font.title)
                .foregroundStyle(AP.Color.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Button("Done", action: onDone)
                .buttonStyle(.plain)
                .font(AP.Font.supporting.weight(.semibold))
                .foregroundStyle(AP.Color.accentText)
                .apMinimumHitTarget()
                .accessibilityIdentifier(Layout.doneIdentifier)
        }
        .padding(.bottom, AP.Space.space12)
    }

    /// Opacity: the glyph, the word, the slider and the value — the reference's strength.
    private var opacityRow: some View {
        HStack(spacing: AP.Space.space12) {
            Image(systemName: "circle.lefthalf.filled")
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.primaryText)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text("Opacity")
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.primaryText)
            Slider(value: Binding(get: { opacity }, set: { onOpacityChange($0) }), in: 0.1...1)
                .tint(AP.Color.accent)
                .disabled(!isEnabled)
                .accessibilityLabel("Pose guide opacity")
                .accessibilityValue("\(Int((opacity * 100).rounded()))%")
                .accessibilityIdentifier(Layout.opacityIdentifier)
            Text("\(Int((opacity * 100).rounded()))%")
                .font(AP.Font.supporting)
                .foregroundStyle(AP.Color.secondaryText)
                .lineLimit(1)
                .frame(width: 48, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
    }

    /// Line colour: four swatches, the chosen one carrying a check glyph as well as its fill.
    private var lineColorRow: some View {
        HStack(spacing: AP.Space.space12) {
            Image(systemName: "eye")
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.primaryText)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text("Line\ncolour")
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.primaryText)
                .fixedSize()
            HStack(spacing: AP.Space.space8) {
                ForEach(GuideLineColor.allCases) { color in
                    swatch(color)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 56)
    }

    private func swatch(_ color: GuideLineColor) -> some View {
        let isSelected = lineColor == color
        return Button {
            onLineColorChange(color)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: AP.Radius.radius8, style: .continuous)
                    .fill(color.swatchColor)
                    .frame(width: 44, height: 44)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(AP.Font.caption.weight(.bold))
                        .foregroundStyle(AP.Color.onAccent)
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("\(color.label) pose line colour")
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(color.accessibilityIdentifier)
    }

    /// Scale: the same value the pinch writes, on a slider, with its percentage.
    private var scaleRow: some View {
        HStack(spacing: AP.Space.space12) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.primaryText)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text("Scale")
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.primaryText)
            Slider(
                value: Binding(get: { scale }, set: { onScaleChange($0) }),
                in: CameraGuideScale.range
            )
            .tint(AP.Color.accent)
            .disabled(!isEnabled)
            .accessibilityLabel("Pose guide scale")
            .accessibilityValue(CameraGuideScale.label(scale))
            .accessibilityIdentifier(Layout.scaleIdentifier)
            Text(CameraGuideScale.label(scale))
                .font(AP.Font.supporting)
                .foregroundStyle(AP.Color.secondaryText)
                .lineLimit(1)
                .fixedSize()
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
    }

    private var flipRow: some View {
        HStack(spacing: AP.Space.space12) {
            Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.primaryText)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text("Flip")
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.primaryText)
            Button(action: onFlip) {
                Text(isFlipped ? "Mirrored" : "Mirror guide")
                    .font(AP.Font.supporting.weight(.semibold))
                    .foregroundStyle(AP.Color.primaryText)
                    .frame(maxWidth: .infinity, minHeight: AP.HitTarget.minimum)
                    .background(
                        RoundedRectangle(cornerRadius: AP.Radius.radius8, style: .continuous)
                            .fill(AP.Color.controlFill)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityLabel(isFlipped ? "Unmirror pose guide" : "Mirror pose guide")
            .accessibilityValue(isFlipped ? "Mirrored" : "Normal")
            .accessibilityIdentifier(Layout.flipIdentifier)
        }
        .frame(minHeight: 52)
    }
}
