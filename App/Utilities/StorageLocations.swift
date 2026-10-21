import Foundation

/// Корневые папки приложения. В тестах подменяется временной директорией.
struct StorageLocations: Sendable {
    /// Documents — видна в «Файлы → На iPhone → Player».
    let documents: URL
    /// Application Support — служебные данные, в «Файлах» не видна.
    let applicationSupport: URL
    /// Caches — то, что можно пересоздать (обложки).
    let caches: URL

    static let standard = StorageLocations(
        documents: URL.documentsDirectory,
        applicationSupport: URL.applicationSupportDirectory,
        caches: URL.cachesDirectory
    )

    /// Сюда копируются импортированные файлы.
    var music: URL { documents.appending(path: "Music", directoryHint: .isDirectory) }
    /// Сюда iOS кладёт файлы из «Открыть в…», если не может открыть их на месте.
    var inbox: URL { documents.appending(path: "Inbox", directoryHint: .isDirectory) }
    /// Файлы из «Открыть в…», которые не удалось импортировать. Их не удаляем,
    /// а откладываем сюда — пользователь видит папку в «Файлах» и решает сам.
    var notImported: URL { documents.appending(path: "Не импортировано", directoryHint: .isDirectory) }
    var libraryIndex: URL { applicationSupport.appending(path: "Library.json") }
    var playbackState: URL { applicationSupport.appending(path: "Playback.json") }
    var artwork: URL { caches.appending(path: "Artwork", directoryHint: .isDirectory) }
    var downloads: URL { caches.appending(path: "Downloads", directoryHint: .isDirectory) }

    /// Абсолютный URL файла по пути относительно Documents.
    func fileURL(forRelativePath path: String) -> URL {
        documents.appending(path: path, directoryHint: .notDirectory)
    }

    /// Путь относительно Documents или `nil`, если файл лежит вне неё.
    /// Симлинки раскрываются: `/var` и `/private/var` — одна и та же папка.
    func relativePath(of url: URL) -> String? {
        let base = documents.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        let full = url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        let prefix = base.hasSuffix("/") ? base : base + "/"
        guard full.hasPrefix(prefix) else { return nil }
        let relative = String(full.dropFirst(prefix.count))
        return relative.isEmpty ? nil : relative
    }

    /// Свободное место на томе с Documents (байты) или `nil`, если неизвестно.
    func availableCapacity() -> Int64? {
        let values = try? documents.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
