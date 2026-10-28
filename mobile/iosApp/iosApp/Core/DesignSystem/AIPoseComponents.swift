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
            NeoHeaderTitle(title: title, subtitle: subtitle, emphasis: titleEmphasis)
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

struct NeoDockTabBar: View {
    @Binding var selection: AppTab
    /// Tab rendered with the active pill. `nil` renders every item inactive, which is what the
    /// prototype does on screens that are not tabs: `search-blank.png` shows both dock icons plain
    /// grey, while `poses-list.png` highlights the Poses item.
    var activeTab: AppTab?
    var body: some View {
        HStack(spacing: AIPoseSpacing.xs) {
            HStack(spacing: 2) {
                dockItem(tab: .poses, icon: "square.grid.2x2", label: "Poses")
                dockItem(tab: .gallery, icon: "photo.on.rectangle", label: "Gallery")
            }
            .padding(2)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .neoSurface(
                shape: Capsule(),
                fill: AIPoseColor.surface,
                borderWidth: NeoChromeTokens.borderThick,
                shadowOffset: NeoChromeTokens.shadowSmall
            )
            Button { selection = .camera } label: {
                Image(systemName: "camera.fill")
                    .font(.body.weight(.bold))
                    .frame(width: 48, height: 48)
                    .foregroundStyle(AIPoseColor.foreground)
                    .neoSurface(
                        shape: Circle(),
                        fill: AIPoseColor.primary,
                        borderWidth: NeoChromeTokens.borderThick,
                        shadowOffset: NeoChromeTokens.shadowSmall
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Camera")
            .accessibilityIdentifier("dock.camera")
        }
        .padding(.horizontal, AIPoseSpacing.lg)
        // The fixed prototype frame has no native home-indicator inset; keep the dock 16pt
        // from the physical screen bottom instead of adding SwiftUI's container safe area.
        .padding(.bottom, AIPoseSpacing.lg)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private func dockItem(tab: AppTab, icon: String, label: String) -> some View {
        let isActive = activeTab == tab
        return Button { selection = tab } label: {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .neoSurface(
                        shape: Capsule(),
                        fill: isActive ? AIPoseColor.accentBlue : .clear,
                        borderColor: isActive ? AIPoseColor.foreground : .clear,
                        borderWidth: NeoChromeTokens.borderThin,
                        shadowOffset: 0
                    )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
