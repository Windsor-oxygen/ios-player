import CoreGraphics
import XCTest
@testable import Player

final class PaletteExtractorTests: XCTestCase {
    /// Изображение из вертикальных полос заданных цветов.
    private func image(stripes: [(UInt8, UInt8, UInt8)], size: Int = 64) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let width = CGFloat(size) / CGFloat(stripes.count)
        for (index, color) in stripes.enumerated() {
            context.setFillColor(red: CGFloat(color.0) / 255, green: CGFloat(color.1) / 255,
                                 blue: CGFloat(color.2) / 255, alpha: 1)
            context.fill(CGRect(x: CGFloat(index) * width, y: 0, width: width, height: CGFloat(size)))
        }
        return try XCTUnwrap(context.makeImage())
    }

    func testFindsDistinctDominantColors() throws {
        let palette = PaletteExtractor.palette(from: try image(stripes: [(220, 30, 30), (30, 60, 220)]))
        XCTAssertGreaterThanOrEqual(palette.count, 2)
        XCTAssertTrue(palette.contains { $0.red > 0.7 && $0.blue < 0.3 }, "Нет красного: \(palette)")
        XCTAssertTrue(palette.contains { $0.blue > 0.7 && $0.red < 0.3 }, "Нет синего: \(palette)")
    }

    func testSolidImageStillGivesGradientPair() throws {
        let palette = PaletteExtractor.palette(from: try image(stripes: [(40, 160, 90)]))
        XCTAssertEqual(palette.count, 2)
        XCTAssertLessThan(palette[1].luminance, palette[0].luminance)
    }

    func testUnreadableFileFallsBack() {
        let palette = PaletteExtractor.palette(fromImageAt: URL(filePath: "/nonexistent/cover.jpg"))
        XCTAssertEqual(palette, PaletteExtractor.fallback)
    }

    func testDarkenKeepsHueAndLowersLuminance() {
        let color = RGBColor(red: 1, green: 0.5, blue: 0.25)
        let dark = color.darkened(toLuminance: 0.2)
        XCTAssertEqual(dark.luminance, 0.2, accuracy: 0.001)
        XCTAssertEqual(dark.red / dark.green, 2, accuracy: 0.001)
        XCTAssertEqual(RGBColor(red: 0.1, green: 0.1, blue: 0.1).darkened(toLuminance: 0.5).red, 0.1)
    }
}
