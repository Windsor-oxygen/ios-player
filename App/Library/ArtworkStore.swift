import CryptoKit
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Дисковый и memory-кэш уменьшенных обложек.
///
/// Обложки, встроенные в файлы, бывают по 3000×3000 px; в списках нужны
/// превью ~112 px, на экране воспроизведения — ~720 px (iPhone 11 — @2x).
/// Ключ — SHA-256 исходных байтов, поэтому треки одного альбома делят файл.
///
/// `@unchecked Sendable`: единственное изменяемое состояние — `NSCache`,
/// который потокобезопасен по документации Apple.
final class ArtworkStore: @unchecked Sendable {
    enum Size: String, CaseIterable, Sendable {
        case small
        case medium
        case large

        var maxPixels: Int {
            switch self {
            case .small: 112
            case .medium: 360
            case .large: 720
            }
        }
    }

    private let directory: URL
    private let memory = NSCache<NSString, UIImage>()

    init(directory: URL) {
        self.directory = directory
        memory.countLimit = 300
    }

    /// Создаёт уменьшенные копии и возвращает ключ. Синхронно, тяжёлое —
    /// вызывать только вне main thread.
    func store(imageData data: Data) -> String? {
        let key = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let fm = FileManager.default
        if Size.allCases.allSatisfy({ fm.fileExists(atPath: fileURL(key: key, size: $0).path(percentEncoded: false)) }) {
            return key
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            for size in Size.allCases {
                guard let thumbnail = Self.thumbnail(from: source, maxPixels: size.maxPixels) else { return nil }
                try Self.writeJPEG(thumbnail, to: fileURL(key: key, size: size))
            }
        } catch {
            Log.library.error("Не удалось сохранить обложку: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return key
    }

    /// Готовое к отрисовке изображение (декодировано вне main thread).
    func image(key: String, size: Size) async -> UIImage? {
        let cacheKey = "\(key)-\(size.rawValue)" as NSString
        if let cached = memory.object(forKey: cacheKey) { return cached }
        guard let loaded = UIImage(contentsOfFile: fileURL(key: key, size: size).path(percentEncoded: false)) else {
            return nil
        }
        let prepared = await loaded.byPreparingForDisplay() ?? loaded
        memory.setObject(prepared, forKey: cacheKey)
        return prepared
    }

    /// Удаляет обложки, на которые больше не ссылается ни один трек.
    func removeUnreferenced(keeping keys: Set<String>) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            let key = name.split(separator: "-").first.map(String.init) ?? name
            if !keys.contains(key) {
                try? fm.removeItem(at: file)
            }
        }
        memory.removeAllObjects()
    }

    private func fileURL(key: String, size: Size) -> URL {
        directory.appending(path: "\(key)-\(size.rawValue).jpg")
    }

    private static func thumbnail(from source: CGImageSource, maxPixels: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func writeJPEG(_ image: CGImage, to url: URL) throws {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        try (data as Data).write(to: url, options: [.atomic])
    }
}
