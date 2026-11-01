import Combine
import SwiftUI
import UIKit
import XCTest
@testable import iosApp

/// What the paywall *draws*, measured on a rendered frame: the iPhone SE (375×667) purchase region,
/// the Accessibility sizes, the status-bar scrim's contrast over the hero, and dark mode resolving
/// from the same tokens. Everything here is a pixel or geometry assertion on real SwiftUI output
/// (`APViewProbe`), not a snapshot diff; the device-level flows stay Maestro's job.
@MainActor
final class PaywallScreenLayoutTests: XCTestCase {
    private let se = CGSize(width: 375, height: 667)
    private let phone = CGSize(width: 430, height: 932)
    private let scale: CGFloat = 2

    // MARK: - Fixtures

    @MainActor
    private final class Gateway: PurchaseGateway {
        private let subject: CurrentValueSubject<PurchaseSnapshot, Never>
        var snapshot: PurchaseSnapshot { subject.value }
        var snapshots: AnyPublisher<PurchaseSnapshot, Never> { subject.eraseToAnyPublisher() }
        private let nextLoad: PurchaseSnapshot

        init(nextLoad: PurchaseSnapshot) {
            self.nextLoad = nextLoad
            subject = CurrentValueSubject(PurchaseSnapshot(state: .notEntitled, products: []))
        }

        func loadOffering() async -> PurchaseSnapshot {
            subject.send(nextLoad)
            return nextLoad
        }

        func purchase(packageID: String) async -> PurchaseSnapshot { subject.value }
        func restore() async -> PurchaseSnapshot { subject.value }
    }

    private let annual = PurchaseProduct(
        identifier: "annual", packageType: .annual, localizedPrice: "$39.99", period: "year"
    )
    private let monthly = PurchaseProduct(
        identifier: "monthly", packageType: .monthly, localizedPrice: "$5.99", period: "month"
    )
    private var offering: PurchaseSnapshot {
        PurchaseSnapshot(state: .notEntitled, products: [monthly, annual])
    }

    /// A model that already settled on a real offering, so the captured frame is a final state.
    private func signedInModel() async -> PaywallModel {
        let model = PaywallModel(
            gateway: Gateway(nextLoad: offering),
            boundary: SessionBoundary(
                tokenStorage: PaywallLayoutTokenStorage(
                    credentials: SessionCredentials(accessToken: "access", refreshToken: "refresh")
                )
            ),
            signInAction: SignInAction(start: {}),
            connectivity: PaywallLayoutConnectivity()
        )
        model.start()
        let deadline = Date().addingTimeInterval(3)
        while model.phase != .ready && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(model.phase, .ready)
        return model
    }

    /// Renders at an explicit size, type size and interface style. The style goes on the probe's key
    /// window, because the design tokens are dynamic `UIColor`s and resolve from the trait collection
    /// (a SwiftUI `colorScheme` environment value would not repaint them).
    private func render(
        _ model: PaywallModel,
        size: CGSize,
        type: DynamicTypeSize = .large,
        style: UIUserInterfaceStyle = .light
    ) -> APBitmap {
        let screen = PaywallScreen(model: model)
            .environment(\.dynamicTypeSize, type)
            .environment(\.sizeCategory, type.contentSizeCategory)
        let probe = APViewProbe(screen, size: size, scale: scale)
        let window = UIApplication.shared.windows.first(where: \.isKeyWindow)
        window?.overrideUserInterfaceStyle = style
        let bitmap = probe.render(screen)
        // The probe's window is shared by every view test in the bundle: leaving a pinned style here
        // would repaint the next test's tokens, so the override ends with this capture.
        window?.overrideUserInterfaceStyle = .unspecified
        probe.tearDown()
        return bitmap
    }

    // MARK: - Hero metrics

    func testHeroHeightIsClampedOnSmallAndLargePhones() {
        XCTAssertEqual(PaywallHeroMetrics.height(for: 667), 187, accuracy: 0.5, "iPhone SE keeps room for the steps")
        XCTAssertEqual(PaywallHeroMetrics.height(for: 932), 261, accuracy: 0.5, "6.7\" phone: ~261 pt")
        XCTAssertEqual(PaywallHeroMetrics.height(for: 480), 180, "never smaller than the 180 pt floor")
        XCTAssertEqual(PaywallHeroMetrics.height(for: 1400), 312, "never taller than the 312 pt ceiling")
        XCTAssertLessThan(PaywallHeroMetrics.height(for: 667), 667 * 0.4, "the hero never eats the viewport")
    }

    // MARK: - iPhone SE: purchase region and escape hatch

    func testSEKeepsTheCloseCtaAndLegalRowInsideTheFrame() async {
        let bitmap = render(await signedInModel(), size: se)

        let cta = bitmap.rows(paintedWith: 0xE89CAE)
        XCTAssertFalse(cta.isEmpty, "the pinned CTA must be painted at 375×667")
        let ctaHeight = Double(cta.count) / Double(scale)
        XCTAssertGreaterThanOrEqual(ctaHeight, 44, "the CTA paints at least the 44 pt hit target")
        XCTAssertLessThan(cta.max()!, bitmap.height - 1, "the CTA is inside the viewport, not clipped")

        let legal = bitmap.rows(paintedWith: 0x8C3350).filter { $0 > cta.max()! }
        XCTAssertFalse(legal.isEmpty, "Restore/Terms/Privacy stay on the first screen below the CTA")
        XCTAssertLessThan(legal.max()!, bitmap.height - 1, "the legal row is never pushed off the bottom")
        let legalInk = bitmap.inkExtent(
            inRows: legal.min()!..<(legal.max()! + 1),
            background: UIColor.tokenPixel(APColorTokens.background.light.uiColor)
        )
        XCTAssertGreaterThan(
            legalInk,
            bitmap.width / 2,
            "all three links are painted across the row, not truncated to one label"
        )

        XCTAssertNotNil(
            closeButton(in: bitmap),
            "the 44 pt close is painted in the first frame, top-trailing, with its X"
        )
    }

    func testXXXLargeKeepsTheCtaAndLegalRowInsideTheFrame() async {
        let bitmap = render(await signedInModel(), size: se, type: .xxxLarge)

        let cta = bitmap.rows(paintedWith: 0xE89CAE)
        XCTAssertFalse(cta.isEmpty, "the CTA survives the larger type at 375 pt")
        XCTAssertGreaterThanOrEqual(Double(cta.count) / Double(scale), 44)
        XCTAssertLessThan(cta.max()!, bitmap.height - 1)

        let legal = bitmap.rows(paintedWith: 0x8C3350).filter { $0 > cta.max()! }
        XCTAssertFalse(legal.isEmpty, "the legal row is still pinned below the CTA at .xxxLarge")
        XCTAssertLessThan(legal.max()!, bitmap.height - 1)
        XCTAssertNotNil(closeButton(in: bitmap))
    }

    func testAccessibilitySizesKeepTheCtaPinnedAndMoveTheLegalRowIntoTheScroll() async {
        for type in [DynamicTypeSize.accessibility1, .accessibility3, .accessibility5] {
            let bitmap = render(await signedInModel(), size: se, type: type)
            let cta = bitmap.rows(paintedWith: 0xE89CAE)
            XCTAssertFalse(cta.isEmpty, "the CTA stays tappable at \(type)")
            XCTAssertLessThan(cta.max()!, bitmap.height - 1, "the CTA is inside the bounds at \(type)")
            XCTAssertFalse(
                PaywallScreen.pinsLegalRow(at: type),
                "at \(type) the legal row moves into the scroll content (reachable, never clipped)"
            )
            XCTAssertNotNil(closeButton(in: bitmap), "the close stays visible at \(type)")
        }
        XCTAssertTrue(PaywallScreen.pinsLegalRow(at: .large))
        XCTAssertTrue(PaywallScreen.pinsLegalRow(at: .xxxLarge))
    }

    // MARK: - Status-bar contrast over the hero

    /// The status bar glyphs are dark over a light background in light mode and white in dark mode, so
    /// each scheme is measured against its own worst case over the brightest hero pixel behind them.
    func testStatusBarScrimMeetsContrastInBothSchemes() async {
        let light = render(await signedInModel(), size: phone, style: .light)
        let lightContrast = contrastOfWorstPixel(in: statusBand(light), against: .black)
        XCTAssertGreaterThanOrEqual(
            lightContrast,
            4.5,
            "dark status glyphs over the cream scrim must clear 4.5:1 (worst pixel: \(lightContrast))"
        )

        let dark = render(await signedInModel(), size: phone, style: .dark)
        let darkContrast = contrastOfWorstPixel(in: statusBand(dark), against: .white)
        XCTAssertGreaterThanOrEqual(
            darkContrast,
            4.5,
            "white status glyphs over the dark scrim must clear 4.5:1 (worst pixel: \(darkContrast))"
        )
    }

    /// The scrim has to be *there*, and it has to follow the scheme: the same photo pixels sit under a
    /// cream wash in light mode and a near-black one in dark mode.
    func testScrimIsAppliedInBothSchemes() async {
        let light = averageLuminance(in: statusBand(render(await signedInModel(), size: phone, style: .light)))
        let dark = averageLuminance(in: statusBand(render(await signedInModel(), size: phone, style: .dark)))
        XCTAssertGreaterThan(light, 0.3, "the light scrim keeps the band light enough for dark glyphs")
        XCTAssertLessThan(dark, 0.2, "the dark scrim keeps the band dark enough for white glyphs")
        XCTAssertGreaterThan(light, dark * 2, "each scheme's scrim resolves from its background token")
    }

    // MARK: - Asset and dark mode

    func testHeroAssetIsBundledAndPainted() async throws {
        let image = try XCTUnwrap(UIImage(named: "paywallHeroC"), "the C hero ships in the asset catalog")
        XCTAssertEqual(image.size.width, 430, accuracy: 1, "the 3x rendition is 1290 px for a 430 pt hero")
        XCTAssertGreaterThan(image.size.height, 0)

        let bitmap = render(await signedInModel(), size: phone)
        let heroBand = band(from: 120 * Int(scale), to: 180 * Int(scale), in: bitmap)
        let background = UIColor.tokenPixel(APColorTokens.background.light.uiColor)
        let painted = heroBand.filter { pixel in
            abs(pixel.red - background.red) > 12
                || abs(pixel.green - background.green) > 12
                || abs(pixel.blue - background.blue) > 12
        }
        XCTAssertGreaterThan(painted.count, heroBand.count / 2, "the hero photo is actually painted")
    }

    func testDarkModePaintsTheDarkBackgroundToken() async {
        let light = render(await signedInModel(), size: se, style: .light)
        let dark = render(await signedInModel(), size: se, style: .dark)
        assertColor(
            light.color(x: 4 * Int(scale), y: light.height - 4 * Int(scale)),
            equals: UIColor.tokenPixel(APColorTokens.background.light.uiColor),
            "light mode paints the cream background token to the bottom edge"
        )
        assertColor(
            dark.color(x: 4 * Int(scale), y: dark.height - 4 * Int(scale)),
            equals: UIColor.tokenPixel(APColorTokens.background.dark.uiColor),
            "dark mode paints the dark background token, not the light one"
        )
    }

    // MARK: - Copy and price discipline

    func testNoPriceIsTypedIntoThePaywallView() throws {
        let source = try paywallViewSource()
        for literal in ["39.99", "5.99", "3.33", "Save 44", "44%"] {
            XCTAssertFalse(source.contains(literal), "\(literal) must come from the store, never from the view")
        }
    }

    func testHeadlineAndStepsAreTheHandoffCopy() {
        XCTAssertEqual(PaywallPlanCopy.headlineLines.joined(separator: " "), "Pick a pose. Match it. Shoot.")
        XCTAssertEqual(PaywallPlanCopy.steps.map(\.title), ["Pick a pose", "Match the outline", "Shoot"])
        XCTAssertEqual(
            PaywallPlanCopy.steps.map(\.detail),
            [
                "Browse and save poses for free.",
                "The guide shows on your live camera.",
                "Premium unlocks the shutter with the full pose camera.",
            ]
        )
        XCTAssertEqual(PaywallPlanCopy.steps.filter(\.isPremium).map(\.id), [3], "only the shutter is paid")
        XCTAssertEqual(PaywallPlanCopy.purchaseCTA, "Unlock the pose camera")
        XCTAssertEqual(
            PaywallPlanCopy.autoRenewCaption,
            "Renews automatically until you cancel in Apple ID settings."
        )
    }

    // MARK: - Helpers

    private enum Reference {
        case black
        case white
    }

    /// The written status-bar band: its glyphs sit in the top ~59 pt, sampled here from 6 pt to 52 pt
    /// and stopping before the close control's column so its white circle cannot be read as backdrop.
    private func statusBand(_ bitmap: APBitmap) -> [APPixel] {
        band(
            from: 6 * Int(scale),
            to: 52 * Int(scale),
            in: bitmap,
            maxColumn: bitmap.width - 110 * Int(scale)
        )
    }

    private func band(
        from startRow: Int,
        to endRow: Int,
        in bitmap: APBitmap,
        maxColumn: Int? = nil
    ) -> [APPixel] {
        var pixels: [APPixel] = []
        let lastColumn = maxColumn ?? bitmap.width
        for y in startRow..<min(endRow, bitmap.height) {
            for x in 0..<min(lastColumn, bitmap.width) {
                if let pixel = bitmap.color(x: x, y: y) { pixels.append(pixel) }
            }
        }
        return pixels
    }

    private func averageLuminance(in pixels: [APPixel]) -> Double {
        guard !pixels.isEmpty else { return 0 }
        return pixels.reduce(0) { $0 + luminance($1) } / Double(pixels.count)
    }

    /// The worst (least contrasty) pixel in the band decides whether the glyphs are legible.
    private func contrastOfWorstPixel(in pixels: [APPixel], against reference: Reference) -> Double {
        let worst = pixels.map(luminance).min(by: { contrast($0, reference) < contrast($1, reference) })
        return contrast(worst ?? 0, reference)
    }

    private func contrast(_ background: Double, _ reference: Reference) -> Double {
        switch reference {
        case .white: return 1.05 / (background + 0.05)
        case .black: return (background + 0.05) / 0.05
        }
    }

    private func luminance(_ pixel: APPixel) -> Double {
        func channel(_ value: Int) -> Double {
            let srgb = Double(value) / 255
            return srgb <= 0.04045 ? srgb / 12.92 : pow((srgb + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(pixel.red) + 0.7152 * channel(pixel.green) + 0.0722 * channel(pixel.blue)
    }

    /// The close control: a `surface`-filled 44 pt rounded square in the top-trailing corner with the
    /// ink X inside it. Returns its painted bounds when it is on screen.
    private func closeButton(in bitmap: APBitmap) -> (rows: ClosedRange<Int>, columns: ClosedRange<Int>)? {
        let surface = UIColor.tokenPixel(APColorTokens.surface.light.uiColor)
        var minRow = bitmap.height, maxRow = -1, minColumn = bitmap.width, maxColumn = -1
        for y in 0..<min(90 * Int(scale), bitmap.height) {
            for x in max(0, bitmap.width - 100 * Int(scale))..<bitmap.width {
                guard let pixel = bitmap.color(x: x, y: y) else { continue }
                guard abs(pixel.red - surface.red) <= 3,
                      abs(pixel.green - surface.green) <= 3,
                      abs(pixel.blue - surface.blue) <= 3 else { continue }
                minRow = min(minRow, y)
                maxRow = max(maxRow, y)
                minColumn = min(minColumn, x)
                maxColumn = max(maxColumn, x)
            }
        }
        guard maxRow > minRow else { return nil }
        let side = Double(max(maxRow - minRow, maxColumn - minColumn) + 1) / Double(scale)
        XCTAssertGreaterThanOrEqual(side, 43, "the close control paints a 44 pt target")
        var hasX = false
        for y in minRow...maxRow where !hasX {
            for x in minColumn...maxColumn {
                guard let pixel = bitmap.color(x: x, y: y) else { continue }
                if luminance(pixel) < 0.06 { hasX = true; break }
            }
        }
        XCTAssertTrue(hasX, "the X glyph is painted inside the close control")
        return (minRow...maxRow, minColumn...maxColumn)
    }

    private func assertColor(_ pixel: APPixel?, equals expected: APPixel, _ message: String) {
        guard let pixel else {
            XCTFail(message)
            return
        }
        XCTAssertEqual(pixel.red, expected.red, accuracy: 3, message)
        XCTAssertEqual(pixel.green, expected.green, accuracy: 3, message)
        XCTAssertEqual(pixel.blue, expected.blue, accuracy: 3, message)
    }

    private func paywallViewSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Features
            .deletingLastPathComponent() // iosAppTests
            .deletingLastPathComponent() // mobile/iosApp
            .appendingPathComponent("iosApp/Features/Support/PaywallScreen.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }
}

// MARK: - Test doubles

@MainActor
final class PaywallLayoutConnectivity: ConnectivityReporting {
    private let subject = CurrentValueSubject<Bool, Never>(false)
    var isOffline: Bool { subject.value }
    var changes: AnyPublisher<Bool, Never> { subject.eraseToAnyPublisher() }
    func start() {}
}

final class PaywallLayoutTokenStorage: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: SessionCredentials?

    init(credentials: SessionCredentials? = nil) {
        self.credentials = credentials
    }

    func saveCredentials(_ credentials: SessionCredentials) {
        lock.lock()
        self.credentials = credentials
        lock.unlock()
    }

    func loadCredentials() -> SessionCredentials? {
        lock.lock()
        defer { lock.unlock() }
        return credentials
    }

    func clearCredentials() {
        lock.lock()
        credentials = nil
        lock.unlock()
    }
}

extension UIColor {
    /// The rendered pixel a resolved dynamic colour paints, so a test compares real output to the
    /// documented token instead of to a second hex constant.
    static func tokenPixel(_ color: UIColor) -> APPixel {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return APPixel(
            red: Int((red * 255).rounded()),
            green: Int((green * 255).rounded()),
            blue: Int((blue * 255).rounded()),
            alpha: Int((alpha * 255).rounded())
        )
    }
}

extension DynamicTypeSize {
    /// The `ContentSizeCategory` the probe also sets, so both Dynamic Type entry points agree in the
    /// rendered frame.
    var contentSizeCategory: ContentSizeCategory {
        switch self {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}
