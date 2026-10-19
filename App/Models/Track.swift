import Foundation

struct Track: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    /// Путь относительно Documents. Абсолютный путь не храним: контейнер
    /// приложения меняет расположение при переустановке.
    var relativePath: String
    var title: String
    var artist: String?
    var album: String?
    var trackNumber: Int?
    var discNumber: Int?
    var duration: TimeInterval
    var fileSize: Int64
    var modificationDate: Date
    var dateAdded: Date
    /// Ключ уменьшенной обложки в `ArtworkStore`.
    var artworkKey: String?
    /// Файл не найден на диске (удалён или перемещён через «Файлы»).
    var isMissing: Bool
    /// Файл есть, но AVFoundation не может его воспроизвести.
    var isUnplayable: Bool
    /// Метаданные ещё не читались или файл изменился.
    var needsMetadata: Bool

    var isAvailable: Bool { !isMissing && !isUnplayable }

    /// Название по умолчанию — имя файла без расширения.
    static func defaultTitle(forRelativePath path: String) -> String {
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return name.isEmpty ? path : name
    }
}
