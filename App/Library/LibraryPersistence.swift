import Foundation

/// Чтение и атомарная запись индекса библиотеки. Работает вне main thread.
///
/// Правило: исходный Library.json не удаляется и не перезаписывается, пока
/// нет его резервной копии. Если файл не читается вовсе — в этой сессии
/// ничего не сохраняем.
actor LibraryPersistence {
    enum LoadOutcome: Equatable, Sendable {
        case loaded(LibraryIndex)
        /// Файла ещё нет — первый запуск.
        case empty
        /// Файл повреждён. Спасено то, что читается; `backupCreated` — сделана ли копия исходника.
        case recovered(LibraryIndex, backupCreated: Bool)
        /// Файл есть, но прочитать его нельзя. Запись заблокирована до перезапуска.
        case unreadable
    }

    enum SaveError: Error {
        /// Запись запрещена, чтобы не затереть файл, который не удалось сохранить в копию.
        case writeProtected
    }

    private let fileURL: URL
    private var isWriteProtected = false
    private var backupBeforeSave = false

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() -> LoadOutcome {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return .empty
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            Log.library.error("Library.json не читается: \(error.localizedDescription, privacy: .public)")
            isWriteProtected = true
            return .unreadable
        }
        do {
            let index = try JSONDecoder().decode(LibraryIndex.self, from: data)
            // Файл от более новой версии приложения: перед первой записью — копия.
            backupBeforeSave = index.version > LibraryIndex.currentVersion
            return .loaded(index)
        } catch {
            Log.library.error("Library.json повреждён: \(error.localizedDescription, privacy: .public)")
            let backupCreated = FileBackup.makeCopy(of: fileURL) != nil
            isWriteProtected = !backupCreated
            return .recovered(LossyLibraryDecoder.decode(data), backupCreated: backupCreated)
        }
    }

    func save(_ index: LibraryIndex) throws {
        guard !isWriteProtected else { throw SaveError.writeProtected }
        if backupBeforeSave {
            guard FileBackup.makeCopy(of: fileURL) != nil else { throw SaveError.writeProtected }
            backupBeforeSave = false
        }
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(index)
        // .atomic пишет во временный файл и подменяет — при сбое старый индекс цел.
        try data.write(to: fileURL, options: [.atomic])
    }
}
