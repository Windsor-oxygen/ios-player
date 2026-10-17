import Foundation

/// Что восстанавливается при следующем запуске: очередь и позиция.
struct PlaybackSnapshot: Codable, Equatable, Sendable {
    var queue: PlaybackQueue
    var position: TimeInterval
}

/// Атомарное сохранение снимка воспроизведения вне main thread.
actor PlaybackSnapshotStore {
    private let fileURL: URL
    /// Номер последнего записанного снимка: более старые запросы игнорируются.
    private var lastSequence = 0

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() -> PlaybackSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PlaybackSnapshot.self, from: data)
    }

    func save(_ snapshot: PlaybackSnapshot, sequence: Int) {
        guard sequence > lastSequence else { return }
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
