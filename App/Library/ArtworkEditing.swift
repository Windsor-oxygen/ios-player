import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Подготовка своей обложки: декодирование уменьшенной копии, квадратная обрезка,
/// сжатие в JPEG. Чистые функции, вызывать вне main thread.
enum ArtworkEditing {
    /// Сторона сохраняемой обложки.
    static let outputSide = 1000
    /// Большие фото декодируем уменьшенными — экономия памяти на A13.
    static let editingMaxPixels = 3000
    private static let jpegQuality = 0.85

    /// Картинка для экрана обрезки (с учётом EXIF-поворота).
    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: editingMaxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Видимый квадрат в координатах картинки. Картинка заполняет квадрат стороной
    /// `viewSide` (scaledToFill), увеличена в `zoom` раз и сдвинута на `offset`.
    static func cropRect(imageSize: CGSize, viewSide: CGFloat, zoom: CGFloat, offset: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, viewSide > 0 else { return .zero }
        let scale = viewSide / min(imageSize.width, imageSize.height) * max(zoom, 1)
        let clamped = clampedOffset(offset, imageSize: imageSize, viewSide: viewSide, zoom: zoom)
        let side = viewSide / scale
        let x = (imageSize.width * scale - viewSide) / 2 - clamped.width
        let y = (imageSize.height * scale - viewSide) / 2 - clamped.height
        return CGRect(x: x / scale, y: y / scale, width: side, height: side).integral
            .intersection(CGRect(origin: .zero, size: imageSize))
    }

    /// Сдвиг, при котором квадрат не выходит за края картинки.
    static func clampedOffset(_ offset: CGSize, imageSize: CGSize, viewSide: CGFloat, zoom: CGFloat) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = viewSide / min(imageSize.width, imageSize.height) * max(zoom, 1)
        let maxX = max((imageSize.width * scale - viewSide) / 2, 0)
        let maxY = max((imageSize.height * scale - viewSide) / 2, 0)
        return CGSize(width: min(max(offset.width, -maxX), maxX), height: min(max(offset.height, -maxY), maxY))
    }

    /// Обрезка и уменьшение до `outputSide` (маленькие картинки не растягиваются), JPEG.
    static func render(_ image: CGImage, crop: CGRect) -> Data? {
        guard let cropped = image.cropping(to: crop) else { return nil }
        let side = min(outputSide, min(cropped.width, cropped.height))
        guard side > 0,
              let context = CGContext(
                  data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return nil }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let output = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, output, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

enum CustomArtworkError: Error, Equatable {
    case unreadableImage
    case saveFailed
    case readOnlyLibrary
}

extension CustomArtworkError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            String(localized: "Не удалось открыть картинку. Выберите другой файл.")
        case .saveFailed:
            String(localized: "Не удалось сохранить обложку. Возможно, на iPhone мало места.")
        case .readOnlyLibrary:
            String(localized: "Библиотека сейчас открыта только для чтения — изменения не сохраняются.")
        }
    }
}
