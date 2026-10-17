import CoreGraphics
import Foundation
import ImageIO

/// Цвет в sRGB, компоненты 0…1.
struct RGBColor: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    /// Воспринимаемая яркость (Rec. 709).
    var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

    var saturation: Double {
        let maxC = max(red, green, blue), minC = min(red, green, blue)
        return maxC == 0 ? 0 : (maxC - minC) / maxC
    }

    /// Затемнить, чтобы белый текст читался на фоне.
    func darkened(toLuminance target: Double) -> RGBColor {
        guard luminance > target, luminance > 0 else { return self }
        let factor = target / luminance
        return RGBColor(red: red * factor, green: green * factor, blue: blue * factor)
    }
}

/// Доминантные цвета обложки. Чистые вычисления на уменьшенном до 24×24
/// изображении — вызывать вне main thread.
enum PaletteExtractor {
    static let fallback = [
        RGBColor(red: 0.17, green: 0.10, blue: 0.40),
        RGBColor(red: 0.05, green: 0.04, blue: 0.13),
    ]

    private static let side = 24

    static func palette(from image: CGImage, count: Int = 3) -> [RGBColor] {
        guard let pixels = rgbaPixels(of: image) else { return fallback }

        // Гистограмма по 4 бита на канал: 4096 корзин.
        struct Bucket { var count = 0.0; var r = 0.0; var g = 0.0; var b = 0.0 }
        var buckets = [Int: Bucket]()
        for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index + 3] > 128 {
            let r = Double(pixels[index]) / 255, g = Double(pixels[index + 1]) / 255, b = Double(pixels[index + 2]) / 255
            let color = RGBColor(red: r, green: g, blue: b)
            // Почти чёрное и почти белое мало что говорит о характере обложки.
            let weight = 0.25 + color.saturation * (color.luminance < 0.06 || color.luminance > 0.94 ? 0.1 : 1)
            let key = Int(pixels[index] >> 4) << 8 | Int(pixels[index + 1] >> 4) << 4 | Int(pixels[index + 2] >> 4)
            var bucket = buckets[key, default: Bucket()]
            bucket.count += weight
            bucket.r += r * weight
            bucket.g += g * weight
            bucket.b += b * weight
            buckets[key] = bucket
        }
        guard !buckets.isEmpty else { return fallback }

        var result: [RGBColor] = []
        for bucket in buckets.values.sorted(by: { $0.count > $1.count }) {
            let color = RGBColor(red: bucket.r / bucket.count, green: bucket.g / bucket.count, blue: bucket.b / bucket.count)
            // Пропускаем почти одинаковые оттенки, чтобы градиент был выразительнее.
            if result.allSatisfy({ distance($0, color) > 0.18 }) {
                result.append(color)
            }
            if result.count == count { break }
        }
        if result.count == 1, let only = result.first {
            result.append(only.darkened(toLuminance: only.luminance * 0.4))
        }
        return result
    }

    static func palette(fromImageAt url: URL) -> [RGBColor] {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: side * 2,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return fallback
        }
        return palette(from: image)
    }

    private static func distance(_ lhs: RGBColor, _ rhs: RGBColor) -> Double {
        let dr = lhs.red - rhs.red, dg = lhs.green - rhs.green, db = lhs.blue - rhs.blue
        return (dr * dr + dg * dg + db * db).squareRoot()
    }

    private static func rgbaPixels(of image: CGImage) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? pixels : nil
    }
}
