import SwiftUI

enum AIPoseColor {
    static let primary = Color(hex: 0xE89CAE)
    static let primary50 = Color(hex: 0xFDF0F3)
    static let primary100 = Color(hex: 0xFAE0E7)
    static let primary700 = Color(hex: 0xD47A90)
    static let primary900 = Color(hex: 0x8C3350)
    static let background = Color(hex: 0xFBF6EF)
    static let surface = Color.white
    static let surfaceVariant = Color(hex: 0xF4F1E8)
    static let foreground = Color(hex: 0x121212)
    static let subtext = Color(hex: 0x6B7280)
    static let border = Color(hex: 0x000000)
    static let success = Color(hex: 0xB5E2B9)
    static let warning = Color(hex: 0xFED766)
    static let error = Color(hex: 0xEE4848)
    static let accentBlue = Color(hex: 0x7FBBE6)
    static let accentYellow = Color(hex: 0xFED766)
    static let accentGreen = Color(hex: 0xB5E2B9)
}

enum AIPoseSpacing {
    static let xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12
    static let lg: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: alpha)
    }
}

struct NeoCardModifier: ViewModifier {
    var background = AIPoseColor.surface
    var cornerRadius: CGFloat = 12
    func body(content: Content) -> some View {
        content.padding(AIPoseSpacing.lg).background(background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(AIPoseColor.foreground, lineWidth: 2))
            .shadow(color: AIPoseColor.foreground, radius: 0, x: 4, y: 4)
    }
}

extension View {
    func neoCard(background: Color = AIPoseColor.surface) -> some View {
        modifier(NeoCardModifier(background: background))
    }
}

struct NeoButtonStyle: ButtonStyle {
    var fill = AIPoseColor.primary
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(AIPoseColor.foreground)
            .frame(maxWidth: .infinity).padding(.vertical, 13).background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AIPoseColor.foreground, lineWidth: 2))
            .shadow(color: AIPoseColor.foreground, radius: 0, x: configuration.isPressed ? 1 : 4, y: configuration.isPressed ? 1 : 4)
            .offset(x: configuration.isPressed ? 3 : 0, y: configuration.isPressed ? 3 : 0)
    }
}

struct FeatureStateView: View {
    let icon: String, title: String, message: String
    var retryTitle: String = "Try again"
    var retry: (() -> Void)?
    var body: some View {
        VStack(spacing: AIPoseSpacing.lg) {
            Image(systemName: icon).font(.system(size: 48)).foregroundStyle(AIPoseColor.subtext)
            Text(title).font(.title2.bold()).foregroundStyle(AIPoseColor.foreground)
            Text(message).multilineTextAlignment(.center).foregroundStyle(AIPoseColor.subtext)
            if let retry { Button(retryTitle, action: retry).buttonStyle(NeoButtonStyle()).padding(.top, AIPoseSpacing.sm) }
        }
        .padding(AIPoseSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
