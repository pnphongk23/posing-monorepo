import SwiftUI

enum NeoFilterChipVariant {
    case standard
    /// `.nb-gallery-filter` from `components/grid.css`.
    case gallery
}

struct NeoFilterChip: View {
    let title: String
    let isSelected: Bool
    var variant: NeoFilterChipVariant = .standard
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            buttonLabel
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var buttonLabel: some View {
        switch variant {
        case .standard:
            styledLabel(
                shape: Capsule(),
                fill: isSelected ? AIPoseColor.accentBlue : AIPoseColor.surface,
                borderWidth: isSelected ? NeoChromeTokens.borderThick : NeoChromeTokens.borderThin,
                shadowOffset: isSelected ? NeoChromeTokens.shadowSelected : NeoChromeTokens.shadowSmall
            )
        case .gallery:
            styledLabel(
                shape: RoundedRectangle(cornerRadius: NeoChromeTokens.radiusSmall),
                fill: isSelected ? AIPoseColor.primary : AIPoseColor.surface,
                borderWidth: isSelected ? NeoChromeTokens.borderThick : NeoChromeTokens.borderThin,
                shadowOffset: isSelected ? NeoChromeTokens.shadowSmall : 0
            )
        }
    }

    private func styledLabel<S: Shape>(
        shape: S,
        fill: Color,
        borderWidth: CGFloat,
        shadowOffset: CGFloat
    ) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .padding(.horizontal, AIPoseSpacing.md)
            .padding(.vertical, AIPoseSpacing.sm)
            .foregroundStyle(AIPoseColor.foreground)
            .neoSurface(
                shape: shape,
                fill: fill,
                borderWidth: borderWidth,
                shadowOffset: shadowOffset
            )
    }
}

struct NeoToolbarTab: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .padding(.horizontal, AIPoseSpacing.lg)
                .padding(.vertical, AIPoseSpacing.sm)
                .neoSurface(
                    shape: RoundedRectangle(cornerRadius: NeoChromeTokens.radiusToolbarTab),
                    fill: isSelected ? AIPoseColor.accentBlue : .clear,
                    borderColor: isSelected ? AIPoseColor.foreground : .clear,
                    borderWidth: NeoChromeTokens.borderThin,
                    shadowOffset: 0
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Square neo-brutalist back control for screens that hide the system navigation bar.
struct NeoBackButton: View {
    var accessibilityLabel: String = "Back"
    /// Gallery detail v2 uses a plain control. `pose-detail.html` uses `.nb-btn--square`, a full 44pt
    /// surface with the regular 3pt hard shadow (the 32pt compact surface is for toolbar actions).
    var plain: Bool = false
    /// Route-specific handle for E2E, set by the owning screen (`poseDetail.back`). Empty by default so
    /// every other back button keeps the label-only contract it already had.
    var accessibilityIdentifier: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if plain {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AIPoseColor.foreground)
                    .frame(width: NeoChromeTokens.touchMinimum, height: NeoChromeTokens.touchMinimum)
                    .contentShape(Circle())
            } else {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AIPoseColor.foreground)
                    .frame(width: NeoChromeTokens.touchMinimum, height: NeoChromeTokens.touchMinimum)
                    .neoSurface(
                        shape: RoundedRectangle(cornerRadius: NeoChromeTokens.radiusMedium),
                        fill: AIPoseColor.surface,
                        borderWidth: NeoChromeTokens.borderThick,
                        shadowOffset: NeoChromeTokens.shadowDefault
                    )
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

/// Boxed square neo-brutalist icon control used inside in-content headers.
struct NeoSquareIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var fill: Color = AIPoseColor.surface
    var side: CGFloat = 36
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AIPoseColor.foreground)
                .frame(width: side, height: side)
                .neoSurface(
                    shape: RoundedRectangle(cornerRadius: NeoChromeTokens.radiusMedium),
                    fill: fill,
                    borderWidth: NeoChromeTokens.borderThin,
                    shadowOffset: NeoChromeTokens.shadowDefault
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Plain circular trailing control used by the Gallery detail v2 topbar.
struct NeoPlainIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AIPoseColor.foreground)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Title emphasis for `NeoSubscreenHeader`.
/// Values come from the prototype tokens: `.nb-nav-bar__title` is 20px/bold
/// (`--nb-type-navigation-title-size`), while the Gallery detail v2 `.topbar__title strong` is 18px/600.
enum NeoHeaderTitleEmphasis {
    case navigation
    case topbar

    var size: CGFloat { self == .navigation ? 20 : 18 }
    var weight: Font.Weight { self == .navigation ? .bold : .semibold }
}

/// Centered title/subtitle stack for `NeoSubscreenHeader`.
struct NeoHeaderTitle: View {
    let title: String
    var subtitle: String?
    var emphasis: NeoHeaderTitleEmphasis = .navigation
    /// Route-specific handle for E2E (`poseDetail.title`). Empty by default so every other title keeps
    /// the label-only contract it already had.
    var identifier: String = ""
    /// Machine-readable identity of what the title names (`poseDetail.title` carries the pose id, so a
    /// flow can compare the pose it left with the pose it came back to).
    var value: String?

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: emphasis.size, weight: emphasis.weight))
                .foregroundStyle(AIPoseColor.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(AIPoseColor.subtext)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(value ?? "")
    }
}

enum NeoSubscreenHeaderMetrics {
    /// Matches the prototype `--nb-touch-min` width of the leading/trailing header columns.
    static let controlColumnWidth: CGFloat = NeoChromeTokens.touchMinimum
}

/// In-content header that replaces the system navigation bar on sub-screens.
/// The title stays optically centered regardless of the leading/trailing control widths.
struct NeoSubscreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var backLabel: String
    /// Route-specific back-button identifier (`poseDetail.back`); empty keeps label-only matching.
    var backIdentifier: String = ""
    /// Route-specific title identifier (`poseDetail.title`); empty keeps label-only matching.
    var titleIdentifier: String = ""
    /// Machine-readable identity the title names (`poseDetail.title` carries the pose id).
    var titleValue: String?
    var plainControls: Bool
    var titleEmphasis: NeoHeaderTitleEmphasis
    var horizontalPadding: CGFloat
    var bottomPadding: CGFloat
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ZStack {
            // The prototype `.nb-nav-bar` is a flex row whose `.nb-nav-bar__left/right` columns are a
            // fixed `--nb-touch-min` (44pt), so the title is constrained between them and can never
            // run under the controls. Mirror that here while keeping the title optically centered.
            NeoHeaderTitle(
                title: title,
                subtitle: subtitle,
                emphasis: titleEmphasis,
                identifier: titleIdentifier,
                value: titleValue
            )
            .padding(.horizontal, NeoSubscreenHeaderMetrics.controlColumnWidth + AIPoseSpacing.sm)
            HStack(spacing: AIPoseSpacing.sm) {
                if let onBack {
                    NeoBackButton(
                        accessibilityLabel: backLabel,
                        plain: plainControls,
                        accessibilityIdentifier: backIdentifier,
                        action: onBack
                    )
                }
                Spacer(minLength: 0)
                trailing()
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, AIPoseSpacing.sm)
        .padding(.bottom, bottomPadding)
    }
}

extension NeoSubscreenHeader where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        backLabel: String = "Back",
        backIdentifier: String = "",
        titleIdentifier: String = "",
        titleValue: String? = nil,
        plainControls: Bool = false,
        titleEmphasis: NeoHeaderTitleEmphasis = .navigation,
        horizontalPadding: CGFloat = AIPoseSpacing.lg,
        bottomPadding: CGFloat = AIPoseSpacing.md,
        onBack: (() -> Void)? = nil
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            backLabel: backLabel,
            backIdentifier: backIdentifier,
            titleIdentifier: titleIdentifier,
            titleValue: titleValue,
            plainControls: plainControls,
            titleEmphasis: titleEmphasis,
            horizontalPadding: horizontalPadding,
            bottomPadding: bottomPadding,
            onBack: onBack,
            trailing: { EmptyView() }
        )
    }
}

extension NeoSubscreenHeader {
    /// Navigation-emphasis header with a single trailing control
    /// (prototype `.nb-nav-bar` + `.nb-nav-bar__right`), which is the common sub-screen shape.
    init(
        title: String,
        subtitle: String? = nil,
        backLabel: String = "Back",
        backIdentifier: String = "",
        titleIdentifier: String = "",
        titleValue: String? = nil,
        plainControls: Bool = false,
        horizontalPadding: CGFloat = AIPoseSpacing.lg,
        bottomPadding: CGFloat = AIPoseSpacing.md,
        onBack: (() -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            backLabel: backLabel,
            backIdentifier: backIdentifier,
            titleIdentifier: titleIdentifier,
            titleValue: titleValue,
            plainControls: plainControls,
            titleEmphasis: .navigation,
            horizontalPadding: horizontalPadding,
            bottomPadding: bottomPadding,
            onBack: onBack,
            trailing: trailing
        )
    }
}

/// Prototype `.nb-btn--compact-action` + `.nb-btn__compact-surface` (`components/nav-bar.css`):
///
/// ```
/// .nb-btn--compact-action  { width: 44px; height: 44px; border: 0; background: transparent; box-shadow: none }
/// .nb-btn__compact-surface { width: 32px; height: 32px; border: 2px solid #000; border-radius: 10px;
///                            background: #fff; box-shadow: 1.5px 1.5px 0 #000 }
/// .nb-btn__compact-surface svg { width: 16px; height: 16px }
/// ```
///
/// The border and shadow belong to the **32pt surface** and the 44pt control around it stays
/// transparent. Putting that chrome on the whole tap target (or inside a system toolbar item) is
/// what makes a nav-bar action read as a heavy black box.
struct NeoCompactActionButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var fill: Color = AIPoseColor.surface
    let action: () -> Void

    private static let surfaceSide: CGFloat = NeoChromeTokens.compactSurfaceSide
    private static let tapSide: CGFloat = NeoChromeTokens.touchMinimum
    private static let cornerRadius: CGFloat = NeoChromeTokens.radiusMedium
    /// The prototype glyph is a 2.5px stroke on a 24 viewBox, i.e. ~1.67pt at the 16pt render size —
    /// `--nb-border-thick` weight, not a heavy icon. `.bold`/`.semibold` fill the surface in and read
    /// as a black blob at this size (verified against `screenshots/reference/poses-list.png`).
    private static let glyphWeight: Font.Weight = .medium

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: Self.glyphWeight))
                .foregroundStyle(AIPoseColor.foreground)
                .frame(width: Self.surfaceSide, height: Self.surfaceSide)
                .neoSurface(
                    shape: RoundedRectangle(cornerRadius: Self.cornerRadius),
                    fill: fill,
                    borderWidth: NeoChromeTokens.borderThick,
                    shadowOffset: NeoChromeTokens.shadowSmall
                )
                // Transparent 44pt tap target around the 32pt surface (`--nb-touch-min`).
                .frame(width: Self.tapSide, height: Self.tapSide)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Hides the system navigation bar on screens that ship their own in-content header.
struct NeoHiddenNavigationBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.toolbar(.hidden, for: .navigationBar)
        } else {
            content.navigationBarHidden(true)
        }
    }
}

extension View {
    func neoHiddenNavigationBar() -> some View {
        modifier(NeoHiddenNavigationBarModifier())
    }
}

/// The shell dock (artboard `01-nav-map` "Dock"): a raised `surface` pill holding Poses and Gallery
/// with a separate raised Camera shutter in the centre. The camera is an action, never a selection,
/// and it opens the full-screen camera with the dock hidden.
///
/// Selected dock items fill with `selectedBackground` and tint `selectedForeground`; the search
/// workspace hides the dock entirely, so `activeTab` can be `nil` (every item plain).
struct NeoDockTabBar: View {
    @Binding var selection: AppTab
    /// Tab rendered with the active fill. `nil` renders every item inactive.
    var activeTab: AppTab?

    /// Pill height and shutter diameter from the artboard's dock.
    static let pillHeight: CGFloat = 60
    static let shutterDiameter: CGFloat = 60
    /// Space the shutter owns in the middle of the pill. The two tab slots are the same size on both
    /// sides of it, so neither tab drifts towards the shutter.
    static let shutterSlot: CGFloat = 60
    static let pillInset: CGFloat = 4

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                dockItem(tab: .poses, icon: "square.grid.2x2", label: "Poses")
                // Reserved for the shutter, so the two slots are symmetric and their content centres
                // on the same line either side of it.
                Color.clear.frame(width: Self.shutterSlot)
                dockItem(tab: .gallery, icon: "photo.on.rectangle", label: "Gallery")
            }
            .padding(Self.pillInset)
            .frame(maxWidth: .infinity)
            .frame(height: Self.pillHeight)
            // Dock chrome does not scale with Dynamic Type (a tab bar keeps its metrics, as iOS does);
            // at AX sizes a scaling label overflows the pill.
            .dynamicTypeSize(.large)
            .background(
                RoundedRectangle(cornerRadius: AP.Radius.radius24, style: .continuous)
                    .fill(AP.Color.surface)
            )
            .apElevation(.e1, cornerRadius: AP.Radius.radius24)

            cameraShutter
                // The shutter straddles the pill's top edge, exactly as the artboard draws it.
                .offset(y: -Self.shutterDiameter / 2 + Self.pillInset)
        }
        // The artboard insets the pill ~40 pt from both edges.
        .padding(.horizontal, AP.Space.space32 + AP.Space.space8)
        // Reserve the space the shutter overflows into, so its upper half is inside the dock's bounds
        // and stays tappable instead of hanging outside the parent's hit area.
        .padding(.top, NeoDockTabBar.shutterDiameter / 2 - Self.pillInset)
        .padding(.bottom, AP.Space.space16)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var cameraShutter: some View {
        Button { selection = .camera } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AP.Color.onAccent)
                .frame(width: Self.shutterDiameter, height: Self.shutterDiameter)
                .background(Circle().fill(AP.Color.accent))
                .apElevation(.e1, cornerRadius: Self.shutterDiameter / 2)
        }
        .buttonStyle(APDockPressStyle())
        .accessibilityLabel("Open Camera")
        .accessibilityIdentifier("dock.camera")
    }

    /// One tab slot. The selected fill hugs the icon + label (a compact pill, not a stretched half),
    /// and the slot centres it in the space the shutter leaves on its side.
    private func dockItem(tab: AppTab, icon: String, label: String) -> some View {
        let isActive = activeTab == tab
        return Button { selection = tab } label: {
            VStack(spacing: AP.Space.space4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(label)
                    .font(AP.Font.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(isActive ? AP.Color.selectedForeground : AP.Color.primaryText)
            .padding(.horizontal, AP.Space.space12)
            .padding(.vertical, AP.Space.space4)
            .frame(minWidth: AP.HitTarget.minimum, minHeight: AP.HitTarget.minimum)
            .background(
                RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                    .fill(isActive ? AP.Color.selectedBackground : Color.clear)
            )
            // Fills the slot so the compact pill stays centred in it.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(APDockPressStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// Press feedback for the dock: fill is owned by the item (selected/unselected), so the style only
/// steps the opacity and scales — and holds still under Reduce Motion.
struct APDockPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        APDockPressBody(configuration: configuration)
    }
}

private struct APDockPressBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? AP.Press.scale : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: AP.Press.duration),
                value: configuration.isPressed
            )
    }
}
