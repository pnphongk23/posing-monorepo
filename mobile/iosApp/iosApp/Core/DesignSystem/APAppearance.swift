// Owner feedback F7: the light/dark toggle leaves the Poses header and becomes an Appearance setting
// (System / Light / Dark). The preference is stored in `UserDefaults`, the same persistence pattern
// the app already uses for its other local preferences, and applied once at the app root.

import SwiftUI

enum APAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "ap_appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// `nil` follows the system appearance.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> APAppearance {
        guard let raw = defaults.string(forKey: storageKey),
              let value = APAppearance(rawValue: raw) else { return .system }
        return value
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.storageKey)
    }
}

/// App-wide appearance state: one observable for the Settings picker and the root modifier.
@MainActor
final class APAppearanceStore: ObservableObject {
    static let shared = APAppearanceStore()

    @Published var appearance: APAppearance {
        didSet { appearance.save(to: defaults) }
    }

    private let defaults: UserDefaults

    /// `defaults` is injectable so tests can use a scratch suite instead of the real one.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = APAppearance.load(from: defaults)
    }
}
