import SwiftUI
import UIKit

/// The shared state contract from artboard 06/07: every state pairs a **glyph and a word** with its
/// colour, so status is never carried by colour alone. Surfaces come from the semantic tokens
/// (`errorSurface`, `warningSurface`, `successSurface`, `controlFill`) and text always lands on
/// `primaryText`, which keeps the documented 11:1–17:1 banner contrast.
enum APStateTone: String, CaseIterable {
    case empty
    case error
    case loading
    case offline
    case success
    case warning

    /// SF Symbol for the state. `.loading` swaps to `staticGlyph` under Reduce Motion.
    var glyph: String {
        switch self {
        case .empty: return "tray"
        case .error: return "exclamationmark.triangle.fill"
        case .loading: return "arrow.triangle.2.circlepath"
        case .offline: return "wifi.slash"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    /// The motion-free alternative: a static arc beside "Loading" instead of a moving one.
    var staticGlyph: String {
        self == .loading ? "circle.dashed" : glyph
    }

    /// The word that ships with the glyph. VoiceOver reads it before the copy.
    var word: String {
        switch self {
        case .empty: return "Empty"
        case .error: return "Error"
        case .loading: return "Loading"
        case .offline: return "Offline"
        case .success: return "Success"
        case .warning: return "Warning"
        }
    }

    var surface: SwiftUI.Color {
        switch self {
        case .empty, .loading: return AP.Color.surface
        case .error: return AP.Color.errorSurface
        case .offline, .warning: return AP.Color.warningSurface
        case .success: return AP.Color.successSurface
        }
    }

    /// The glyph colour inside the banner. Every one of these clears 3:1 against `surface`.
    var glyphColor: SwiftUI.Color {
        switch self {
        case .empty: return AP.Color.secondaryText
        case .error: return AP.Color.error
        case .loading: return AP.Color.secondaryText
        case .offline, .warning: return AP.Color.warning
        case .success: return AP.Color.success
        }
    }
}

/// Flat skeleton: a `controlFill` bar whose only motion is an opacity pulse. Reduce Motion pins it to
/// the resting opacity, which the tests assert directly.
enum APSkeleton {
    static let barHeight: CGFloat = 12
    static let restingOpacity: Double = 1
    static let pulsingOpacity: Double = 0.55
    static let pulseDuration: Double = 0.9

    static func opacity(isPulsing: Bool, reduceMotion: Bool) -> Double {
        guard !reduceMotion, isPulsing else { return restingOpacity }
        return pulsingOpacity
    }
}

/// One flat skeleton bar.
struct APSkeletonBar: View {
    var width: CGFloat?
    var height: CGFloat = APSkeleton.barHeight
    var opacity: Double = APSkeleton.restingOpacity

    var body: some View {
        RoundedRectangle(cornerRadius: AP.Radius.radius8, style: .continuous)
            .fill(AP.Color.controlFill)
            .frame(maxWidth: width ?? .infinity)
            .frame(height: height)
            .opacity(opacity)
    }
}

/// Glyph + word row. Shared by the banners and the loading state so the pairing cannot drift.
struct APStateWordRow: View {
    let tone: APStateTone
    var word: String
    var useStaticGlyph: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AP.Space.space8) {
            Image(systemName: useStaticGlyph ? tone.staticGlyph : tone.glyph)
                .font(AP.Font.caption)
                .foregroundStyle(tone.glyphColor)
                .accessibilityHidden(true)
            Text(word)
                .font(AP.Font.caption.weight(.semibold))
                .foregroundStyle(AP.Color.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// How a state panel is mounted.
enum APStateCardStyle {
    /// Raised `surface` card (E1, radius 24) for surfaces that group the state with other content.
    case card
    /// Borderless, centred panel on the screen background, with the glyph on a tone tile — the
    /// catalogue and Search state panels (artboards `02-poses-home-error`, `02-poses-home-no-matches`).
    case plain
}

/// Empty state: glyph, title, copy and an optional action, as a raised card or a plain panel.
struct APEmptyStateView: View {
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var style: APStateCardStyle = .card
    /// Panel glyph override (Saved uses the bookmark, not the empty tray).
    var glyph: String?

    var body: some View {
        APStateCard(
            tone: .empty,
            glyphOverride: glyph,
            showsWord: false,
            title: title,
            message: message,
            actionTitle: actionTitle,
            actionKind: .secondary,
            action: action,
            style: style
        )
    }
}

/// Recoverable error: the error surface, a glyph + word, and the primary recovery action
/// (`02-poses-home-error`: the pink "Try again" button). VoiceOver announces it because the state is
/// the reason the screen is not showing content.
struct APErrorStateView: View {
    var title: String
    var message: String
    var retryTitle: String = "Try again"
    var retry: (() -> Void)?
    var style: APStateCardStyle = .card
    /// Panel glyph override.
    var glyph: String?

    @State private var didAnnounce = false

    var body: some View {
        APStateCard(
            tone: .error,
            glyphOverride: glyph,
            showsWord: style == .card,
            title: title,
            message: message,
            actionTitle: retry == nil ? nil : retryTitle,
            actionKind: .primary,
            action: retry,
            style: style
        )
        .onAppear(perform: announceIfNeeded)
    }

    private func announceIfNeeded() {
        guard !didAnnounce else { return }
        didAnnounce = true
        let text = [APStateTone.error.word, title, message].filter { !$0.isEmpty }.joined(separator: ". ")
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}

/// The shared panel behind the empty and error states.
///
/// `.card` is a raised `surface` block (E1, radius 24, no resting border; the dark edge is the
/// elevation modifier's `cardStroke` hairline). `.plain` is the catalogue panel: no chrome at all, the
/// glyph on a tone-coloured tile, centred copy and one action.
private struct APStateCard: View {
    let tone: APStateTone
    /// Optional glyph override (Saved uses the bookmark, not the tray).
    let glyphOverride: String?
    let showsWord: Bool
    let title: String
    let message: String
    let actionTitle: String?
    let actionKind: APButtonKind
    let action: (() -> Void)?
    let style: APStateCardStyle

    var body: some View {
        VStack(spacing: style == .card ? AP.Space.space12 : AP.Space.space16) {
            glyph
            if showsWord {
                APStateWordRow(tone: tone, word: tone.word)
            }
            Text(title)
                .font(AP.Font.title)
                .foregroundStyle(AP.Color.primaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(actionStyle)
                    .fixedSize(horizontal: style == .plain, vertical: false)
                    .padding(.top, AP.Space.space4)
            }
        }
        .padding(chromePadding)
        .frame(maxWidth: .infinity, maxHeight: style == .plain ? .infinity : nil)
        .background(cardBackground)
        .accessibilityElement(children: action == nil ? .combine : .contain)
    }

    @ViewBuilder private var glyph: some View {
        switch style {
        case .card:
            Image(systemName: glyphOverride ?? tone.glyph)
                .font(.system(.largeTitle, design: .default))
                .foregroundStyle(tone.glyphColor)
                .accessibilityHidden(true)
        case .plain:
            Image(systemName: glyphOverride ?? tone.glyph)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(tone.glyphColor)
                .frame(width: 72, height: 72)
                .background(
                    RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                        .fill(tone.surface)
                )
                .accessibilityHidden(true)
        }
    }

    private var actionStyle: APButtonStyleForKind {
        APButtonStyleForKind(kind: actionKind)
    }

    private var chromePadding: EdgeInsets {
        switch style {
        case .card:
            return EdgeInsets(top: AP.Space.space24, leading: AP.Space.space24,
                              bottom: AP.Space.space24, trailing: AP.Space.space24)
        case .plain:
            return EdgeInsets(top: AP.Space.space24, leading: AP.Space.space32,
                              bottom: AP.Space.space24, trailing: AP.Space.space32)
        }
    }

    @ViewBuilder private var cardBackground: some View {
        switch style {
        case .card:
            RoundedRectangle(cornerRadius: AP.Radius.radius24, style: .continuous)
                .fill(tone.surface)
                .apElevation(.e1, cornerRadius: AP.Radius.radius24)
        case .plain:
            Color.clear
        }
    }
}

/// Loading: flat `controlFill` skeleton rows plus a glyph + word. The skeleton pulses its opacity;
/// under Reduce Motion it stays static and the row shows a static arc.
struct APLoadingStateView: View {
    var label: String = "Loading"
    var rows: Int = 3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: AP.Space.space12) {
            APStateWordRow(tone: .loading, word: label, useStaticGlyph: reduceMotion)
            VStack(alignment: .leading, spacing: AP.Space.space8) {
                ForEach(Array(0..<max(rows, 1)), id: \.self) { index in
                    APSkeletonBar(
                        width: index == rows - 1 ? 160 : nil,
                        opacity: APSkeleton.opacity(isPulsing: isPulsing, reduceMotion: reduceMotion)
                    )
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .onAppear(perform: startPulse)
    }

    private func startPulse() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: APSkeleton.pulseDuration).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }
}

/// Offline banner: `warningSurface`, glyph + word, copy that says what still works, optional retry.
struct APOfflineBanner: View {
    var message: String = "No internet. Showing saved poses."
    var retryTitle: String? = "Retry"
    var retry: (() -> Void)?

    var body: some View {
        APStatusBanner(
            tone: .offline,
            title: message,
            actionTitle: retry == nil ? nil : retryTitle,
            action: retry
        )
    }
}

/// Small status banner: success / warning / error (offline is the warning variant above). Flat, radius
/// 16, radius24 never applies — E0 by design, no shadow and no border.
struct APStatusBanner: View {
    var tone: APStateTone
    var title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: AP.Space.space8) {
            APStateWordRow(tone: tone, word: tone.word)
            VStack(alignment: .leading, spacing: AP.Space.space4) {
                Text(title)
                    .font(AP.Font.supporting)
                    .foregroundStyle(AP.Color.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message)
                        .font(AP.Font.caption)
                        .foregroundStyle(AP.Color.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(APChipButtonStyle())
            }
        }
        .padding(AP.Space.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                .fill(tone.surface)
        )
        // No hand-written label: combining the children lets SwiftUI build the announcement from the
        // Text views that are actually drawn (word, then title, then copy).
        .accessibilityElement(children: action == nil ? .combine : .contain)
    }
}
