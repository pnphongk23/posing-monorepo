import SwiftUI

/// The pose reference's stroke colour, as the guide-adjust sheet's swatches offer it.
enum GuideLineColor: String, CaseIterable, Identifiable, Sendable {
    case pink, black, yellow, green

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// The stroke and the swatch fill. Pink is the brand accent and black is ink (both the same in every
    /// appearance); yellow and green are the palette's **fills** (`warningSurface` / `successSurface`), not its inks
    /// — the ink tokens are dark brown and dark green in light mode, which is not the board's yellow and mint.
    ///
    /// All four are fixed colours, not scheme-dependent ones: the reference is drawn on the camera's dark stage and
    /// picked on the light sheet, and it has to look the same in both.
    var color: Color {
        switch self {
        case .pink: return AP.Color.accent
        case .black: return AP.Color.onAccent
        case .yellow: return Self.fixed(APColorTokens.warningSurface)
        case .green: return Self.fixed(APColorTokens.successSurface)
        }
    }

    /// A token's light value as a fixed colour (the palette does not follow the appearance).
    private static func fixed(_ token: APColorToken) -> Color {
        Color(uiColor: token.spec(for: .light).uiColor)
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

/// Hosts a SwiftUI subtree with the interface style pinned to its own trait collection.
///
/// The AP colour tokens are dynamic `UIColor`s (`Color(uiColor:)`), so they resolve from the **trait
/// collection**, not from `\.colorScheme`: `.environment(\.colorScheme, .light)` alone leaves them dark inside a
/// dark screen. A child hosting controller with `overrideUserInterfaceStyle` is the trait the tokens actually
/// follow, and it keeps the override local — the camera behind the sheet stays dark.
struct APInterfaceStyleHost<Content: View>: UIViewControllerRepresentable {
    let style: UIUserInterfaceStyle
    @ViewBuilder let content: () -> Content

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let controller = UIHostingController(rootView: content())
        controller.overrideUserInterfaceStyle = style
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ controller: UIHostingController<Content>, context: Context) {
        controller.rootView = content()
        controller.overrideUserInterfaceStyle = style
    }
}

/// The adjust sheet's slider, drawn the way the board draws it: a 6 pt track whose filled part is the accent text
/// colour and whose rest is the palette's olive-grey (`disabled`), with a 28 pt dark disc for the thumb.
///
/// SwiftUI's `Slider` cannot restyle its thumb — it draws a white pill — so the sheet draws its own, with the same
/// drag-and-adjust behaviour (and the same adjustable accessibility) as the camera band's zoom control.
///
/// Every number below is measured on `05-camera-guide-adjust.png` at the 393 reference.
struct CameraAdjustSlider: View {
    let value: CGFloat
    let range: ClosedRange<CGFloat>
    var isEnabled = true
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let onChange: (CGFloat) -> Void

    static let thumbDiameter: CGFloat = 28
    static let trackHeight: CGFloat = 6
    static let height: CGFloat = 44

    var body: some View {
        GeometryReader { proxy in
            let travel = max(proxy.size.width - Self.thumbDiameter, 1)
            let fraction = Self.fraction(of: value, in: range)
            let thumbX = Self.thumbDiameter / 2 + travel * fraction
            let centreY = proxy.size.height / 2

            ZStack(alignment: .topLeading) {
                // The whole track, in the board's olive-grey…
                Capsule()
                    .fill(AP.Color.disabled)
                    .frame(width: travel, height: Self.trackHeight)
                    .position(x: proxy.size.width / 2, y: centreY)
                // …the part behind the value in the accent text colour…
                Capsule()
                    .fill(AP.Color.accentText)
                    .frame(width: max(thumbX - Self.thumbDiameter / 2, 0), height: Self.trackHeight)
                    .position(x: max(thumbX - Self.thumbDiameter / 2, 0) / 2, y: centreY)
                // …and the dark disc on top of it.
                Circle()
                    .fill(AP.Color.onAccent)
                    .frame(width: Self.thumbDiameter, height: Self.thumbDiameter)
                    .position(x: thumbX, y: centreY)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard isEnabled else { return }
                        let raw = (drag.location.x - Self.thumbDiameter / 2) / travel
                        onChange(Self.factor(atFraction: raw, in: range))
                    }
            )
        }
        .frame(height: Self.height)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(Self.percentLabel(value, in: range))
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            let step = (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: onChange(min(value + step, range.upperBound))
            case .decrement: onChange(max(value - step, range.lowerBound))
            @unknown default: break
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    static func fraction(of value: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    static func factor(atFraction fraction: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        let clamped = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        return range.lowerBound + clamped * (range.upperBound - range.lowerBound)
    }

    static func percentLabel(_ value: CGFloat, in range: ClosedRange<CGFloat>) -> String {
        "\(Int((fraction(of: value, in: range) * 100).rounded()))%"
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
    let onReset: () -> Void
    let onDone: () -> Void

    /// The sheet's handles. `camera.guideAdjust` is the sheet itself (a container), the rest are its controls.
    enum Layout {
        static let sheetIdentifier = "camera.guideAdjust"
        static let opacityIdentifier = "camera.guideAdjust.opacity"
        static let scaleIdentifier = "camera.guideAdjust.scale"
        static let flipIdentifier = "camera.guideAdjust.flip"
        static let resetIdentifier = "camera.guideAdjust.reset"
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
            resetRow
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AP.Space.space16)
        .padding(.bottom, AP.Space.space16)
        .frame(maxWidth: .infinity)
        .frame(height: Layout.height, alignment: .top)
        .background(
            // The board's sheet is the app's cream background, not the white card surface.
            RoundedTopShape(radius: AP.Radius.radius24)
                .fill(AP.Color.background)
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
            CameraAdjustSlider(
                value: CGFloat(opacity),
                range: 0.1...1,
                isEnabled: isEnabled,
                accessibilityLabel: "Pose guide opacity",
                accessibilityIdentifier: Layout.opacityIdentifier,
                onChange: { onOpacityChange(Double($0)) }
            )
            .accessibilityValue("\(Int((opacity * 100).rounded()))%")
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
            CameraAdjustSlider(
                value: scale,
                range: CameraGuideScale.range,
                isEnabled: isEnabled,
                accessibilityLabel: "Pose guide scale",
                accessibilityIdentifier: Layout.scaleIdentifier,
                onChange: onScaleChange
            )
            .accessibilityValue(CameraGuideScale.label(scale))
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

    private var resetRow: some View {
        HStack {
            Spacer(minLength: 0)
            Button("Reset", action: onReset)
                .buttonStyle(.plain)
                .font(AP.Font.supporting.weight(.semibold))
                .foregroundStyle(AP.Color.accentText)
                .apMinimumHitTarget()
                .disabled(!isEnabled)
                .accessibilityIdentifier(Layout.resetIdentifier)
        }
        .frame(minHeight: AP.HitTarget.minimum)
    }
}
