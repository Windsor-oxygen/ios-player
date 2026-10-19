import Foundation

/// Что восстанавливается при следующем запуске: очередь и позиция.
struct PlaybackSnapshot: Codable, Equatable, Sendable {
    var queue: PlaybackQueue
    var position: TimeInterval
}

/// Атомарное сохранение снимка воспроизведения вне main thread.
/// Нечитаемый файл не перезаписывается без резервной копии.
actor PlaybackSnapshotStore {
    private let fileURL: URL
    /// Номер последнего записанного снимка: более старые запросы игнорируются.
    private var lastSequence = 0
    private var isWriteProtected = false

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() -> PlaybackSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(PlaybackSnapshot.self, from: data)
        } catch {
            Log.playback.error("Playback.json не читается: \(error.localizedDescription, privacy: .public)")
            isWriteProtected = FileBackup.makeCopy(of: fileURL) == nil
            return nil
        }
    }

    func save(_ snapshot: PlaybackSnapshot, sequence: Int) {
        guard sequence > lastSequence, !isWriteProtected else { return }
        lastSequence = sequence
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try JSONEncoder().encode(snapshot).write(to: fileURL, options: [.atomic])
        } catch {
            Log.playback.error("Не удалось сохранить состояние: \(error.localizedDescription, privacy: .public)")
        }
    }
}
