import Foundation

/// Чтение и атомарная запись индекса библиотеки. Работает вне main thread.
actor LibraryPersistence {
    enum LoadOutcome: Equatable, Sendable {
        case loaded(LibraryIndex)
        /// Файла ещё нет — первый запуск.
        case empty
        /// Файл был повреждён; он переименован в `.corrupt`, начинаем с пустого индекса.
        case recoveredFromCorruption
    }

    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() -> LoadOutcome {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            return .empty
        }
        do {
            let index = try JSONDecoder().decode(LibraryIndex.self, from: data)
            return .loaded(index)
        } catch {
            Log.library.error("Library.json повреждён: \(error.localizedDescription, privacy: .public)")
            let backup = fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return .recoveredFromCorruption
        }
    }

    func save(_ index: LibraryIndex) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(index)
        // .atomic пишет во временный файл и подменяет — при сбое старый индекс цел.
        try data.write(to: fileURL, options: [.atomic])
    }
}
