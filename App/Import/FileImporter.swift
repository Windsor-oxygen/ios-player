import AVFoundation

enum ImportError: Error, Equatable, Sendable {
    case unsupportedFormat(String)
    case notAudio(String)
    case insufficientSpace
    case accessDenied
    case unreadable
    case copyFailed(String)
}

extension ImportError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            String(localized: "Формат .\(ext) не поддерживается iOS.")
        case .notAudio(let name):
            String(localized: "«\(name)» — не аудиофайл.")
        case .insufficientSpace:
            String(localized: "Недостаточно места на iPhone.")
        case .accessDenied:
            String(localized: "Нет доступа к файлу.")
        case .unreadable:
            String(localized: "Файл повреждён или не воспроизводится.")
        case .copyFailed(let reason):
            String(localized: "Не удалось скопировать файл: \(reason)")
        }
    }
}

/// Итог импорта пачки файлов — показывается пользователю одним сообщением.
struct ImportReport: Equatable, Sendable {
    struct Failure: Equatable, Sendable {
        let fileName: String
        let error: ImportError
    }

    var importedPaths: [String] = []
    var failures: [Failure] = []
    /// Сколько файлов отложено в «Не импортировано» (а не удалено).
    var setAsideCount = 0

    /// Сколько ошибок перечислять в сообщении поимённо.
    static let maxListedFailures = 5
}

/// Копирование файлов в Documents/Music. Все методы синхронные или
/// nonisolated async — выполняются вне main thread.
struct FileImporter: Sendable {
    /// Запас свободного места сверх размера файла.
    static let spaceMargin: Int64 = 20 * 1024 * 1024

    let locations: StorageLocations

    func importFiles(_ urls: [URL]) async -> ImportReport {
        var report = ImportReport()
        for url in urls {
            do {
                let path = try await importFile(url)
                report.importedPaths.append(path)
            } catch let error as ImportError {
                Log.importing.notice("Не импортирован \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
                report.failures.append(.init(fileName: url.lastPathComponent, error: error))
            } catch {
                report.failures.append(.init(fileName: url.lastPathComponent, error: .copyFailed(error.localizedDescription)))
            }
        }
        return report
    }

    /// Импортирует один файл и возвращает путь относительно Documents.
    func importFile(_ source: URL) async throws -> String {
        switch AudioFormat.classify(source) {
        case .supported:
            break
        case .unsupported(let ext):
            throw ImportError.unsupportedFormat(ext)
        case .notAudio:
            throw ImportError.notAudio(source.lastPathComponent)
        }

        // Файл уже в нашей папке (например, «Открыть в» с Documents) — копировать не нужно,
        // кроме Inbox: туда iOS кладёт временные копии, их переносим в Music.
        if let relative = locations.relativePath(of: source), !isInInbox(source) {
            return relative
        }

        let accessing = source.startAccessingSecurityScopedResource()
        defer {
            if accessing { source.stopAccessingSecurityScopedResource() }
        }

        let fromInbox = isInInbox(source)
        let destination = try copyIntoMusic(source, preferredName: source.lastPathComponent, move: fromInbox)
        guard await isPlayable(destination) else {
            if fromInbox {
                // Файл перенесён из Inbox — это единственная копия, её не удаляем.
                setAside(destination)
            } else {
                // Это наша копия; оригинал остался там, откуда его выбрали.
                try? FileManager.default.removeItem(at: destination)
            }
            throw ImportError.unreadable
        }
        return try relativePathOrThrow(destination)
    }

    /// Переносит загруженный файл из временной папки в Music.
    /// Невоспроизводимую загрузку удаляем: это не файл пользователя, а наш временный.
    func importDownloaded(_ staged: URL, fileName: String) async throws -> String {
        let destination = try copyIntoMusic(staged, preferredName: fileName, move: true)
        guard await isPlayable(destination) else {
            try? FileManager.default.removeItem(at: destination)
            throw ImportError.unreadable
        }
        return try relativePathOrThrow(destination)
    }

    /// Файлы, оставшиеся в Documents/Inbox (например, после выгрузки приложения), — в Music.
    func drainInbox() async -> ImportReport {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: locations.inbox, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return ImportReport() }
        let setAsideBefore = setAsideFileCount()
        var report = await importFiles(files)
        // Импортированное уже перенесено в Music. Остальное не удаляем, а откладываем.
        for file in files where fm.fileExists(atPath: file.path(percentEncoded: false)) {
            setAside(file)
        }
        report.setAsideCount = max(setAsideFileCount() - setAsideBefore, 0)
        return report
    }

    private func setAsideFileCount() -> Int {
        let path = locations.notImported.path(percentEncoded: false)
        return (try? FileManager.default.contentsOfDirectory(atPath: path))?.count ?? 0
    }

    /// Переносит файл в «Не импортировано». Если не вышло — оставляет на месте.
    private func setAside(_ file: URL) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: locations.notImported, withIntermediateDirectories: true)
            try fm.moveItem(at: file, to: uniqueDestination(for: file.lastPathComponent, in: locations.notImported))
        } catch {
            Log.importing.error("Не удалось отложить \(file.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Helpers

    func uniqueDestination(for fileName: String, in directory: URL) -> URL {
        let fm = FileManager.default
        let sanitized = Self.sanitize(fileName)
        let base = (sanitized as NSString).deletingPathExtension
        let ext = (sanitized as NSString).pathExtension
        var candidate = directory.appending(path: sanitized)
        var counter = 2
        while fm.fileExists(atPath: candidate.path(percentEncoded: false)) {
            let name = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            candidate = directory.appending(path: name)
            counter += 1
        }
        return candidate
    }

    static func sanitize(_ fileName: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.controlCharacters)
        let cleaned = fileName.components(separatedBy: invalid).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutLeadingDots = String(cleaned.drop(while: { $0 == "." }))
        return withoutLeadingDots.isEmpty ? "Track" : withoutLeadingDots
    }

    private func copyIntoMusic(_ source: URL, preferredName: String, move: Bool) throws -> URL {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: locations.music, withIntermediateDirectories: true)
        } catch {
            throw ImportError.copyFailed(error.localizedDescription)
        }
        let size = Int64((try? source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        if let available = locations.availableCapacity(), available < size + Self.spaceMargin {
            throw ImportError.insufficientSpace
        }
        let destination = uniqueDestination(for: preferredName, in: locations.music)
        do {
            if move {
                try fm.moveItem(at: source, to: destination)
            } else {
                try Self.coordinatedCopy(from: source, to: destination)
            }
        } catch let error as CocoaError where error.code == .fileWriteOutOfSpace {
            throw ImportError.insufficientSpace
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            throw ImportError.accessDenied
        } catch {
            throw ImportError.copyFailed(error.localizedDescription)
        }
        return destination
    }

    /// Копирование через NSFileCoordinator: файлы iCloud Drive и других
    /// провайдеров при этом докачиваются, а не копируются «заглушкой».
    private static func coordinatedCopy(from source: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [.withoutChanges], error: &coordinationError) { readURL in
            do {
                try FileManager.default.copyItem(at: readURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
    }

    private func relativePathOrThrow(_ url: URL) throws -> String {
        guard let relative = locations.relativePath(of: url) else {
            throw ImportError.copyFailed(url.lastPathComponent)
        }
        return relative
    }

    private func isInInbox(_ url: URL) -> Bool {
        guard let relative = locations.relativePath(of: url) else { return false }
        return relative.hasPrefix("Inbox/")
    }

    private func isPlayable(_ url: URL) async -> Bool {
        (try? await AVURLAsset(url: url).load(.isPlayable)) ?? false
    }
}
