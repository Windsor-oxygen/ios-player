import CoreImage
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
    private let palettes = NSCache<NSString, PaletteBox>()
    /// CIContext потокобезопасен и дорог в создании — один на приложение.
    private let ciContext = CIContext()

    init(directory: URL) {
        self.directory = directory
        // Лимит по объёму декодированных пикселей, а не по количеству: одна обложка
        // 720 px — это ~2 МБ, 360 px — ~0,5 МБ.
        memory.totalCostLimit = 48 * 1024 * 1024
        palettes.countLimit = 100
    }

    /// Создаёт уменьшенные копии и возвращает ключ. Синхронно, тяжёлое —
    /// вызывать только вне main thread.
    func store(imageData data: Data) -> String? {
        let key = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if hasImages(key: key) {
            return key
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        do {
            try prepareDirectory()
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

    /// Все размеры миниатюр на диске.
    func hasImages(key: String) -> Bool {
        Size.allCases.allSatisfy {
            FileManager.default.fileExists(atPath: fileURL(key: key, size: $0).path(percentEncoded: false))
        }
    }

    /// 1.0/1.1 хранили миниатюры в Caches, которые iOS очищает при нехватке места.
    /// Переносим уцелевшее в новую папку (это наш кэш, не файлы пользователя).
    static func migrate(from legacy: URL, to directory: URL) {
        let fm = FileManager.default
        defer { excludeFromBackup(directory) }
        guard fm.fileExists(atPath: legacy.path(percentEncoded: false)) else { return }
        if !fm.fileExists(atPath: directory.path(percentEncoded: false)) {
            try? fm.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? fm.moveItem(at: legacy, to: directory)) != nil {
                Log.library.notice("Миниатюры обложек перенесены из Caches")
                return
            }
        }
        let files = (try? fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            let target = directory.appending(path: file.lastPathComponent)
            if !fm.fileExists(atPath: target.path(percentEncoded: false)) {
                try? fm.moveItem(at: file, to: target)
            }
        }
        try? fm.removeItem(at: legacy)
    }

    /// Готовое к отрисовке изображение (декодировано вне main thread).
    func image(key: String, size: Size) async -> UIImage? {
        let cacheKey = "\(key)-\(size.rawValue)" as NSString
        if let cached = memory.object(forKey: cacheKey) { return cached }
        guard let loaded = UIImage(contentsOfFile: fileURL(key: key, size: size).path(percentEncoded: false)) else {
            return nil
        }
        let prepared = await loaded.byPreparingForDisplay() ?? loaded
        memory.setObject(prepared, forKey: cacheKey, cost: Self.cost(of: prepared))
        return prepared
    }

    /// Размытая обложка для фона экрана воспроизведения. Размываем один раз
    /// (Core Image, вне main thread), а не фильтром SwiftUI на каждом кадре.
    func backdrop(key: String) async -> UIImage? {
        let cacheKey = "\(key)-backdrop" as NSString
        if let cached = memory.object(forKey: cacheKey) { return cached }
        guard let source = UIImage(contentsOfFile: fileURL(key: key, size: .medium).path(percentEncoded: false)),
              let cgImage = source.cgImage else { return nil }
        let input = CIImage(cgImage: cgImage)
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: 24).cropped(to: input.extent)
        guard let output = ciContext.createCGImage(blurred, from: input.extent) else { return nil }
        let image = UIImage(cgImage: output)
        memory.setObject(image, forKey: cacheKey, cost: Self.cost(of: image))
        return image
    }

    /// Доминантные цвета обложки для динамического фона (кэш в памяти и на диске).
    func palette(key: String) async -> [RGBColor] {
        let cacheKey = key as NSString
        if let cached = palettes.object(forKey: cacheKey) { return cached.colors }
        let file = directory.appending(path: "\(key)-palette.json")
        if let data = try? Data(contentsOf: file),
           let colors = try? JSONDecoder().decode([RGBColor].self, from: data) {
            palettes.setObject(PaletteBox(colors), forKey: cacheKey)
            return colors
        }
        let colors = PaletteExtractor.palette(fromImageAt: fileURL(key: key, size: .small))
        if let data = try? JSONEncoder().encode(colors) {
            try? data.write(to: file, options: [.atomic])
        }
        palettes.setObject(PaletteBox(colors), forKey: cacheKey)
        return colors
    }

    /// Удаляет обложки, на которые больше не ссылается ни один трек.
    /// Свежие файлы (моложе минуты) не трогаем: их мог только что создать
    /// параллельный импорт, а ключ ещё не попал в библиотеку.
    func removeUnreferenced(keeping keys: Set<String>) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let threshold = Date.now.addingTimeInterval(-60)
        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            let key = name.split(separator: "-").first.map(String.init) ?? name
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if !keys.contains(key), (modified ?? .distantPast) < threshold {
                try? fm.removeItem(at: file)
            }
        }
        memory.removeAllObjects()
        palettes.removeAllObjects()
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Self.excludeFromBackup(directory)
    }

    /// Папка миниатюр не попадает в бэкап iCloud: её всегда можно пересоздать.
    private static func excludeFromBackup(_ directory: URL) {
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = directory
        try? url.setResourceValues(values)
    }

    private static func cost(of image: UIImage) -> Int {
        Int(image.size.width * image.scale * image.size.height * image.scale * 4)
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

/// Обёртка для хранения палитры в NSCache (нужен class).
private final class PaletteBox {
    let colors: [RGBColor]

    init(_ colors: [RGBColor]) {
        self.colors = colors
    }
}
