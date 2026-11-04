import SwiftUI

/// The camera tools popover: four one-line rows anchored under the tools control — the camera's whole settings
/// surface, kept in its own file because it is a surface, not a corner of the screen.
///
/// `.nb-camera-tools-menu` height: the prototype's `max-height` is a cap, not a target. The menu carries
/// eleven rows once a pose guide is in place, and on a phone that content is taller than a fixed cap — so
/// the guide rows were clipped inside the popover's own scroll view: present in the accessibility tree,
/// hittable by nobody. The popover may use the whole safe area it is given instead.
enum CameraToolsPopupMetrics {
    /// Floor: a cramped screen still gets a scrollable window rather than a sliver.
    static let minHeight = AP.Space.space48

    static func maxHeight(
        available: CGFloat,
        topBarBottom: CGFloat,
        bottomMargin: CGFloat = AP.Space.space16
    ) -> CGFloat {
        max(minHeight, available - topBarBottom - bottomMargin)
    }
}

/// The camera tools popover's surface contract (owner feedback, build 18).
///
/// There is no title row and no Done action: every control applies and persists the moment it changes,
/// and the popover is dismissed by tapping outside or with VoiceOver's escape. The identifiers below are
/// the ones the rows expose, so "the Done handle is gone" is a unit-testable fact rather than a memory.
enum CameraToolsLayout {
    static let hasHeaderRow = false
    /// Retired with the Done button; no row may expose it again.
    static let retiredDoneIdentifier = "camera.tools.done"
    static let controlIdentifiers = [
        "camera.tools.flash",
        "camera.tools.grid",
        "camera.tools.mirror",
        "camera.tools.timer",
        "camera.tools.ratio",
        "camera.tools.poseGuide",
        "camera.tools.opacity",
        "camera.tools.scale",
        "camera.tools.lineColor.black",
        "camera.tools.lineColor.white",
    ]

    /// Every change lands on the model directly (no commit step), so a setting is persisted while the
    /// popover is still open.
    static func persistsImmediately(identifier: String) -> Bool {
        controlIdentifiers.contains(identifier)
    }
}

// MARK: - Camera tools (AP tokens, forced dark)

/// The camera's settings surface: an anchored popup under the tools control (no scrim, no handle, no
/// app-bar Close), `surface` fill, radius 24, E1 — the dark card edge is the elevation's `cardStroke`
/// hairline, never a hand-drawn border. Rows are `controlFill` pills with 44 pt targets and a pressed
/// fill step, and every status pairs a glyph with a word.
///
/// The popup hugs its content up to `max-height` with `overflow-y: auto`, so the content height is
/// measured once through a preference and the scroll view is bounded to it.
struct CameraToolsPopup: View {
    let flashSetting: CameraFlashSetting
    let isGridVisible: Bool
    let controlsEnabled: Bool
    let hasPose: Bool
    let isPoseGuideVisible: Bool
    let guideFlipped: Bool
    let timerSetting: CameraTimerSetting
    let aspectRatio: CameraAspectRatio
    let guideOpacity: Double
    let guideScale: CGFloat
    let guideLineColor: GuideLineColor
    let popupWidth: CGFloat
    let popupMaxHeight: CGFloat
    let onFlashTap: () -> Void
    let onGridToggle: () -> Void
    let onPoseGuideVisibilityToggle: () -> Void
    let onMirrorToggle: () -> Void
    let onTimerChange: (CameraTimerSetting) -> Void
    let onAspectRatioChange: (CameraAspectRatio) -> Void
    let onGuideScaleChange: (CGFloat) -> Void
    let onGuideScaleReset: () -> Void
    let onGuideOpacityChange: (Double) -> Void
    let onGuideLineColorChange: (GuideLineColor) -> Void
    let onDismiss: () -> Void

    @State private var naturalContentHeight: CGFloat?

    var body: some View {
        ScrollView {
            content
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: CameraToolsContentHeightKey.self,
                            value: geo.size.height
                        )
                    }
                )
        }
        .onPreferenceChange(CameraToolsContentHeightKey.self) { naturalContentHeight = $0 }
        .frame(maxWidth: popupWidth, alignment: .leading)
        .modifier(CameraToolsPopupHeight(naturalHeight: naturalContentHeight, maxHeight: popupMaxHeight))
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius24, style: .continuous)
                .fill(AP.Color.surface)
        )
        .apElevation(.e1, cornerRadius: AP.Radius.radius24)
        .clipShape(RoundedRectangle(cornerRadius: AP.Radius.radius24, style: .continuous))
        .accessibilityElement(children: .contain)
        // VoiceOver's local Back (two-finger Z scrub) — the native equivalent of Escape.
        .accessibilityAction(.escape) { onDismiss() }
    }

    /// A four-point rhythm: the menu carries eleven rows once a pose guide is up, and at the row spacing
    /// of the rest of the chrome the guide section fell below the fold of the safe area it is given.
    private var content: some View {
        VStack(alignment: .leading, spacing: AP.Space.space4) {
            row(
                systemImage: flashSetting.symbolName,
                title: "Flash",
                value: flashSetting.toolsDisplayName,
                accessibilityLabel: "Flash \(flashSetting.toolsDisplayName), tap to change",
                identifier: "camera.tools.flash",
                action: onFlashTap
            )
            gridRow
            timerRow
            ratioRow

            if hasPose {
                Divider()
                    .overlay(AP.Color.separator)
                    .padding(.vertical, AP.Space.space4)

                Text("Pose guide")
                    .font(AP.Font.caption)
                    .foregroundStyle(AP.Color.secondaryText)
                    .accessibilityAddTraits(.isHeader)

                row(
                    systemImage: isPoseGuideVisible ? "eye" : "eye.slash",
                    title: "Pose guide",
                    value: isPoseGuideVisible ? "Shown" : "Hidden",
                    accessibilityLabel: isPoseGuideVisible ? "Hide pose guide" : "Show pose guide",
                    identifier: "camera.tools.poseGuide",
                    action: onPoseGuideVisibilityToggle
                )
                mirrorRow
                opacityRow
                guideScaleRow
                lineColorRow
            }
        }
        .padding(AP.Space.space12)
    }

    /// One settings row: glyph + word on `controlFill`, 44 pt tall, pressed fill step.
    private func row(
        systemImage: String?,
        title: String,
        value: String?,
        accessibilityLabel: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AP.Space.space8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(AP.Font.body)
                        .foregroundStyle(AP.Color.primaryText)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(AP.Font.body)
                    .foregroundStyle(AP.Color.primaryText)
                Spacer(minLength: AP.Space.space8)
                if let value {
                    Text(value)
                        .font(AP.Font.body.weight(.semibold))
                        .foregroundStyle(AP.Color.accentText)
                }
            }
            .padding(.horizontal, AP.Space.space12)
            .frame(maxWidth: .infinity, minHeight: AP.HitTarget.minimum, alignment: .leading)
        }
        .buttonStyle(CameraRowStyle())
        .disabled(!controlsEnabled)
        .opacity(controlsEnabled ? 1 : 0.45)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier)
    }

    private var gridRow: some View {
        HStack(spacing: AP.Space.space8) {
            Image(systemName: "grid")
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.primaryText)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text("Grid")
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.primaryText)
            Spacer(minLength: AP.Space.space8)
            gridSwitch
        }
        .padding(.horizontal, AP.Space.space12)
        .frame(maxWidth: .infinity, minHeight: AP.HitTarget.minimum, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                .fill(AP.Color.controlFill)
        )
        .opacity(controlsEnabled ? 1 : 0.45)
        .accessibilityLabel("Show camera grid")
        .accessibilityIdentifier("camera.tools.grid")
    }

    /// Switch: `accent` track when on, `controlFillPressed` when off, ink knob, 44 pt hit area.
    private var gridSwitch: some View {
        Button(action: onGridToggle) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(isGridVisible ? AP.Color.accent : AP.Color.controlFillPressed)
                    .frame(width: 48, height: 28)
                Circle()
                    .fill(AP.Color.onAccent)
                    .frame(width: 22, height: 22)
                    .padding(.leading, 3)
                    .offset(x: isGridVisible ? 20 : 0)
            }
            .animation(.easeOut(duration: 0.1), value: isGridVisible)
        }
        .buttonStyle(.plain)
        // The drawn switch is 48x28; the row's own minimum height does not enlarge the Button, so the
        // target is applied here, where the tap actually lands.
        .apMinimumHitTarget()
        .disabled(!controlsEnabled)
        .accessibilityLabel("Show camera grid")
        .accessibilityValue(isGridVisible ? "On" : "Off")
        .accessibilityIdentifier("camera.tools.grid")
        .accessibilityAddTraits(isGridVisible ? [.isSelected] : [])
    }

    /// Opacity: label + value on the tone's ink, slider tinted with the accent.
    /// Mirror: flips the pose reference (the guide), with a glyph and a word so the state is never
    /// carried by the switch's own position.
    private var mirrorRow: some View {
        HStack(spacing: AP.Space.space8) {
            Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.primaryText)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text("Mirror guide")
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.primaryText)
            Spacer(minLength: AP.Space.space8)
            Text(guideFlipped ? "Mirrored" : "Normal")
                .font(AP.Font.body.weight(.semibold))
                .foregroundStyle(AP.Color.accentText)
            mirrorSwitch
        }
        .padding(.horizontal, AP.Space.space12)
        .frame(maxWidth: .infinity, minHeight: AP.HitTarget.minimum, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                .fill(AP.Color.controlFill)
        )
        .opacity(controlsEnabled ? 1 : 0.45)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera.tools.mirror")
    }

    private var mirrorSwitch: some View {
        Button(action: onMirrorToggle) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(guideFlipped ? AP.Color.accent : AP.Color.controlFillPressed)
                    .frame(width: 48, height: 28)
                Circle()
                    .fill(AP.Color.onAccent)
                    .frame(width: 22, height: 22)
                    .padding(.leading, 3)
                    .offset(x: guideFlipped ? 20 : 0)
            }
            .animation(.easeOut(duration: 0.1), value: guideFlipped)
        }
        .buttonStyle(.plain)
        .apMinimumHitTarget()
        .disabled(!controlsEnabled)
        .accessibilityLabel("Mirror pose guide")
        .accessibilityValue(guideFlipped ? "Mirrored" : "Normal")
        .accessibilityIdentifier("camera.tools.mirror.switch")
        .accessibilityAddTraits(guideFlipped ? [.isSelected] : [])
    }

    /// Pose reference's size: value, slider and a Reset, so the gesture has a visible control.
    private var guideScaleRow: some View {
        VStack(alignment: .leading, spacing: AP.Space.space4) {
            HStack(spacing: AP.Space.space8) {
                Text("Scale")
                    .font(AP.Font.body)
                    .foregroundStyle(AP.Color.primaryText)
                Spacer(minLength: AP.Space.space8)
                Text(CameraGuideScale.label(guideScale))
                    .font(AP.Font.body.weight(.semibold))
                    .foregroundStyle(AP.Color.accentText)
            }
            HStack(spacing: AP.Space.space8) {
                Slider(
                    value: Binding(get: { guideScale }, set: { onGuideScaleChange($0) }),
                    in: CameraGuideScale.range
                )
                .tint(AP.Color.accent)
                .disabled(!controlsEnabled)
                .accessibilityLabel("Pose guide scale \(CameraGuideScale.label(guideScale))")
                .accessibilityIdentifier("camera.tools.scale")

                Button("Reset", action: onGuideScaleReset)
                    .buttonStyle(.plain)
                    .font(AP.Font.supporting.weight(.semibold))
                    .foregroundStyle(AP.Color.accentText)
                    .apMinimumHitTarget()
                    .disabled(!controlsEnabled)
                    .accessibilityIdentifier("camera.tools.scale.reset")
            }
        }
        .padding(.horizontal, AP.Space.space12)
        .padding(.vertical, AP.Space.space8)
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                .fill(AP.Color.controlFill)
        )
        .opacity(controlsEnabled ? 1 : 0.45)
    }

    /// Ratio: the saved capture's aspect. The chosen option carries a check glyph and its word.
    private var ratioRow: some View {
        VStack(alignment: .leading, spacing: AP.Space.space4) {
            HStack(spacing: AP.Space.space8) {
                Image(systemName: "rectangle.portrait")
                    .font(AP.Font.body)
                    .foregroundStyle(AP.Color.primaryText)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text("Ratio")
                    .font(AP.Font.body)
                    .foregroundStyle(AP.Color.primaryText)
                Spacer(minLength: AP.Space.space8)
                Text(aspectRatio.rawValue)
                    .font(AP.Font.body.weight(.semibold))
                    .foregroundStyle(AP.Color.accentText)
            }
            HStack(spacing: AP.Space.space8) {
                ForEach(CameraAspectRatio.allCases) { ratio in
                    ratioChoice(ratio)
                }
            }
        }
        .padding(.horizontal, AP.Space.space12)
        .padding(.vertical, AP.Space.space8)
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                .fill(AP.Color.controlFill)
        )
        .disabled(!controlsEnabled)
        .opacity(controlsEnabled ? 1 : 0.45)
        // A container, not a single element: each Ratio choice keeps its own identifier
        // (`camera.tools.ratio.*`) while the row keeps `camera.tools.ratio`.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera.tools.ratio")
    }

    private func ratioChoice(_ ratio: CameraAspectRatio) -> some View {
        let isSelected = aspectRatio == ratio
        return Button {
            onAspectRatioChange(ratio)
        } label: {
            HStack(spacing: AP.Space.space4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(AP.Font.caption.weight(.bold))
                }
                Text(ratio.rawValue)
                    .font(AP.Font.supporting.weight(.semibold))
            }
            .foregroundStyle(isSelected ? AP.Color.selectedForeground : AP.Color.primaryText)
            .frame(maxWidth: .infinity, minHeight: AP.HitTarget.minimum)
        }
        .buttonStyle(CameraSelectStyle(isSelected: isSelected))
        .accessibilityLabel("Ratio \(ratio.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(ratio.accessibilityIdentifier)
    }

    /// Timer: Off / 3 s / 10 s, the chosen option with a check glyph and its word.
    private var timerRow: some View {
        VStack(alignment: .leading, spacing: AP.Space.space4) {
            HStack(spacing: AP.Space.space8) {
                Image(systemName: "timer")
                    .font(AP.Font.body)
                    .foregroundStyle(AP.Color.primaryText)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text("Timer")
                    .font(AP.Font.body)
                    .foregroundStyle(AP.Color.primaryText)
                Spacer(minLength: AP.Space.space8)
                Text(timerSetting.rawValue)
                    .font(AP.Font.body.weight(.semibold))
                    .foregroundStyle(AP.Color.accentText)
            }
            HStack(spacing: AP.Space.space8) {
                ForEach(CameraTimerSetting.allCases) { setting in
                    timerChoice(setting)
                }
            }
        }
        .padding(.horizontal, AP.Space.space12)
        .padding(.vertical, AP.Space.space8)
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                .fill(AP.Color.controlFill)
        )
        .disabled(!controlsEnabled)
        .opacity(controlsEnabled ? 1 : 0.45)
        // A container, not a single element: each Timer choice keeps its own identifier
        // (`camera.tools.timer.*`) while the row keeps `camera.tools.timer`.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera.tools.timer")
    }

    private func timerChoice(_ setting: CameraTimerSetting) -> some View {
        let isSelected = timerSetting == setting
        return Button {
            onTimerChange(setting)
        } label: {
            HStack(spacing: AP.Space.space4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(AP.Font.caption.weight(.bold))
                }
                Text(setting.rawValue)
                    .font(AP.Font.supporting.weight(.semibold))
            }
            .foregroundStyle(isSelected ? AP.Color.selectedForeground : AP.Color.primaryText)
            .frame(maxWidth: .infinity, minHeight: AP.HitTarget.minimum)
        }
        .buttonStyle(CameraSelectStyle(isSelected: isSelected))
        .accessibilityLabel("Timer \(setting.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(setting.accessibilityIdentifier)
    }

    private var opacityRow: some View {
        VStack(alignment: .leading, spacing: AP.Space.space4) {
            HStack(spacing: AP.Space.space8) {
                Text("Opacity")
                    .font(AP.Font.body)
                    .foregroundStyle(AP.Color.primaryText)
                Spacer(minLength: AP.Space.space8)
                Text("\(Int((guideOpacity * 100).rounded()))%")
                    .font(AP.Font.body.weight(.semibold))
                    .foregroundStyle(AP.Color.accentText)
            }
            Slider(value: Binding(
                get: { guideOpacity },
                set: { onGuideOpacityChange($0) }
            ), in: 0.1...1)
            .tint(AP.Color.accent)
            .disabled(!controlsEnabled)
            .accessibilityLabel("Pose guide opacity \(Int((guideOpacity * 100).rounded())) percent")
            .accessibilityIdentifier("camera.tools.opacity")
        }
        .padding(.horizontal, AP.Space.space12)
        .padding(.vertical, AP.Space.space8)
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                .fill(AP.Color.controlFill)
        )
    }

    /// Line colour: the selected choice carries a check glyph **and** its word, never colour alone.
    private var lineColorRow: some View {
        VStack(alignment: .leading, spacing: AP.Space.space4) {
            Text("Line colour")
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.primaryText)
            HStack(spacing: AP.Space.space8) {
                choiceButton(.black, identifier: "camera.tools.lineColor.black")
                choiceButton(.white, identifier: "camera.tools.lineColor.white")
            }
        }
        .padding(.horizontal, AP.Space.space12)
        .padding(.vertical, AP.Space.space8)
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                .fill(AP.Color.controlFill)
        )
        .disabled(!controlsEnabled)
        .opacity(controlsEnabled ? 1 : 0.45)
    }

    private func choiceButton(_ color: GuideLineColor, identifier: String) -> some View {
        let isSelected = guideLineColor == color
        return Button {
            onGuideLineColorChange(color)
        } label: {
            HStack(spacing: AP.Space.space4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(AP.Font.caption.weight(.bold))
                }
                Text(color.label)
                    .font(AP.Font.supporting.weight(.semibold))
            }
            .foregroundStyle(isSelected ? AP.Color.selectedForeground : AP.Color.primaryText)
            .frame(maxWidth: .infinity, minHeight: AP.HitTarget.minimum)
        }
        .buttonStyle(CameraSelectStyle(isSelected: isSelected))
        .accessibilityLabel("\(color.label) pose line colour")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// Selected/unselected fill for an option chip: `selectedBackground` when chosen, else transparent
/// (it sits on the row's `controlFill`).
private struct CameraSelectStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: AP.Radius.radius8, style: .continuous)
                    .fill(isSelected ? AP.Color.selectedBackground
                          : (configuration.isPressed ? AP.Color.controlFillPressed : Color.clear))
            )
            .apMinimumHitTarget()
    }
}

/// `controlFill` row with a pressed fill step.
private struct CameraRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                    .fill(configuration.isPressed ? AP.Color.controlFillPressed : AP.Color.controlFill)
            )
            .apMinimumHitTarget()
    }
}

private struct CameraToolsContentHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// `max-height: min(62vh, 420px)` + `overflow-y: auto`, while hugging the content when it is
/// shorter than the cap (the prototype menu is not a fixed-height panel).
private struct CameraToolsPopupHeight: ViewModifier {
    let naturalHeight: CGFloat?
    let maxHeight: CGFloat

    func body(content: Content) -> some View {
        if let naturalHeight, naturalHeight > 0 {
            content.frame(height: min(naturalHeight, maxHeight))
        } else {
            content.frame(maxHeight: maxHeight)
        }
    }
}

