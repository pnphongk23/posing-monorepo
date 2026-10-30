import SwiftUI
import UIKit
import XCTest

/// Renders a SwiftUI view in a real key window so tests can assert on pixels SwiftUI actually painted.
///
/// One shared window is reused on purpose: SwiftUI only renders into the key window, so a test that
/// spins up a second window after the first is torn down gets a blank frame. Tests that compare two
/// renders therefore reuse one probe and swap the root view through `render(_:)`.
@MainActor
final class APViewProbe {
    private static var sharedWindow: UIWindow?

    private let window: UIWindow
    private let host: UIHostingController<AnyView>
    private let size: CGSize
    private let scale: CGFloat

    /// - Parameter scale: pixels per point in the capture. Use 2+ for geometry assertions: at scale 1 a
    ///   half-point layout phase shifts a 2 pt band by a whole pixel and makes the test flaky.
    init<V: View>(_ view: V, size: CGSize = CGSize(width: 320, height: 240), scale: CGFloat = 1) {
        self.size = size
        self.scale = scale
        let window = Self.window()
        self.window = window
        window.frame = CGRect(origin: .zero, size: size)
        host = UIHostingController(rootView: AnyView(view))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = CGRect(origin: .zero, size: size)
        settle()
    }

    /// Pumps layout and the run loop, so SwiftUI has committed what the first pass queued.
    func settle() {
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
    }

    /// Renders a different root view in the same window and captures it.
    func render<V: View>(_ view: V) -> APBitmap {
        host.rootView = AnyView(view)
        return capture()
    }

    func capture() -> APBitmap {
        settle()
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        return APBitmap(image: image)
            ?? APBitmap(width: Int(size.width * scale), height: Int(size.height * scale))
    }

    func tearDown() {
        host.view.removeFromSuperview()
        if window.rootViewController === host {
            window.rootViewController = nil
        }
    }

    private static func window() -> UIWindow {
        if let sharedWindow {
            return sharedWindow
        }
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        }
        window.windowLevel = .normal + 1
        // Opaque white, so a capture has a known background instead of a transparent one.
        window.backgroundColor = .white
        sharedWindow = window
        return window
    }
}

/// One rendered pixel, top-down.
struct APPixel {
    let red: Int
    let green: Int
    let blue: Int
    let alpha: Int
}

/// Pixel view of a rendered frame. Coordinates are top-down, like the screen.
struct APBitmap {
    let bytes: [UInt8]
    let width: Int
    let height: Int

    init?(image: UIImage) {
        guard let cg = image.cgImage else { return nil }
        let pixelWidth = cg.width
        let pixelHeight = cg.height
        width = pixelWidth
        height = pixelHeight
        var buffer = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            return true
        }
        guard drawn else { return nil }
        bytes = buffer
    }

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        bytes = [UInt8](repeating: 0, count: width * height * 4)
    }

    func color(x: Int, y: Int) -> APPixel? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        // Drawn into a bottom-up context, so buffer row 0 is the top row of the screen.
        let index = (y * width + x) * 4
        guard index >= 0, index + 3 < bytes.count else { return nil }
        return APPixel(
            red: Int(bytes[index]), green: Int(bytes[index + 1]),
            blue: Int(bytes[index + 2]), alpha: Int(bytes[index + 3])
        )
    }

    /// Rows that paint `hex` at least once. Locates a painted control without assuming its frame.
    func rows(paintedWith hex: UInt32, tolerance: Int = 6) -> [Int] {
        let target = (red: Int((hex >> 16) & 0xFF), green: Int((hex >> 8) & 0xFF), blue: Int(hex & 0xFF))
        var rows: [Int] = []
        for y in 0..<height {
            for x in 0..<width {
                guard let pixel = color(x: x, y: y), pixel.alpha > 200 else { continue }
                if abs(pixel.red - target.red) <= tolerance,
                   abs(pixel.green - target.green) <= tolerance,
                   abs(pixel.blue - target.blue) <= tolerance {
                    rows.append(y)
                    break
                }
            }
        }
        return rows
    }

    /// Column extent of the ink (non-background pixels) in a row band. Text widening the words it
    /// draws grows this number; a row that paints no text keeps it at zero.
    func inkExtent(inRows rows: Range<Int>, background: APPixel = APPixel(red: 255, green: 255, blue: 255, alpha: 255)) -> Int {
        var left: Int?
        var right: Int?
        for y in rows where y >= 0 && y < height {
            for x in 0..<width {
                guard let pixel = color(x: x, y: y), pixel.alpha > 200 else { continue }
                let differs = abs(pixel.red - background.red) > 8
                    || abs(pixel.green - background.green) > 8
                    || abs(pixel.blue - background.blue) > 8
                guard differs else { continue }
                left = min(left ?? x, x)
                right = max(right ?? x, x)
            }
        }
        guard let left, let right else { return 0 }
        return right - left + 1
    }

    /// Whether two renders disagree anywhere in a row band. Proves that a piece of copy is painted:
    /// swapping the copy has to change the pixels it occupies.
    func differs(from other: APBitmap, inRows rows: Range<Int>, tolerance: Int = 4) -> Bool {
        for y in rows where y >= 0 && y < min(height, other.height) {
            for x in 0..<min(width, other.width) {
                guard let mine = color(x: x, y: y), let theirs = other.color(x: x, y: y) else { return true }
                if abs(mine.red - theirs.red) > tolerance
                    || abs(mine.green - theirs.green) > tolerance
                    || abs(mine.blue - theirs.blue) > tolerance {
                    return true
                }
            }
        }
        return false
    }
}
