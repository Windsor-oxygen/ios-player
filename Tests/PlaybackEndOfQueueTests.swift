import MediaPlayer
import XCTest
@testable import Player

/// Конец очереди на настоящем `AVQueuePlayer`: короткий тихий WAV доигрывает,
/// движок должен остановиться на первом треке очереди на паузе — без падения
/// и без повторного запуска. Повторяет сценарий скриншота 09 (демо-режим).
@MainActor
final class PlaybackEndOfQueueTests: XCTestCase {
    private struct Setup {
        let locations: StorageLocations
        let library: LibraryStore
        let engine: PlaybackEngine
    }

    private func makeSetup(files: [String: Double], snapshot: ((LibraryStore) -> PlaybackSnapshot?)? = nil) async throws -> Setup {
        let locations = try TestSupport.makeLocations()
        for (title, seconds) in files {
            try TestSupport.write(TestSupport.wavData(seconds: seconds), to: locations.music.appending(path: "\(title).wav"))
        }
        let name = "PlayerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let library = LibraryStore(locations: locations, defaults: defaults)
        await library.refresh()
        if let saved = snapshot?(library) {
            try TestSupport.write(try JSONEncoder().encode(saved), to: locations.playbackState)
        }
        let engine = PlaybackEngine(library: library, settings: AppSettings(defaults: defaults), locations: locations)
        return Setup(locations: locations, library: library, engine: engine)
    }

    private func trackID(_ title: String, in library: LibraryStore) throws -> UUID {
        try XCTUnwrap(library.tracks.first { $0.title == title }?.id, "Нет трека «\(title)»")
    }

    /// Ждёт условие, давая главному потоку обрабатывать события плеера.
    private func wait(timeout: TimeInterval, until condition: () -> Bool) async -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return condition()
    }

    func testSingleShortTrackStopsAtStartOfQueue() async throws {
        let setup = try await makeSetup(files: ["Короткий": 1])
        defer { TestSupport.cleanUp(setup.locations) }
        let engine = setup.engine
        let id = try trackID("Короткий", in: setup.library)

        engine.play([id])
        XCTAssertTrue(engine.isPlaying)
        let finished = await wait(timeout: 10) { !engine.isPlaying }
        XCTAssertTrue(finished, "Трек длиной 1 с не доиграл за 10 с")
        // Даём дойти отложенным уведомлениям (KVO, didPlayToEnd) — повторного старта быть не должно.
        try await Task.sleep(for: .seconds(2))

        XCTAssertEqual(engine.currentTrack?.id, id)
        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(engine.queue.currentIndex, 0)
        XCTAssertEqual(engine.clock.currentTime, 0, accuracy: 0.5)

        // После конца очереди «Играть» снова работает.
        XCTAssertEqual(engine.play(), .success)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(engine.currentTrack?.id, id)
        _ = engine.pause()
    }

    /// Последовательность демо-сценария: восстановление сохранённой позиции,
    /// затем запуск другого, короткого трека, который доигрывает.
    func testPlayingShortTrackAfterRestoreFinishesCleanly() async throws {
        let setup = try await makeSetup(files: ["Длинный": 100, "Короткий": 1]) { library in
            guard let long = library.tracks.first(where: { $0.title == "Длинный" }) else { return nil }
            var queue = PlaybackQueue()
            queue.replace(with: [long.id], startAt: 0, shuffled: false)
            return PlaybackSnapshot(queue: queue, position: 74)
        }
        defer { TestSupport.cleanUp(setup.locations) }
        let engine = setup.engine
        let long = try trackID("Длинный", in: setup.library)
        let short = try trackID("Короткий", in: setup.library)

        await engine.restore()
        XCTAssertEqual(engine.currentTrack?.id, long)
        XCTAssertFalse(engine.isPlaying)

        engine.play([short])
        XCTAssertEqual(engine.currentTrack?.id, short)
        let finished = await wait(timeout: 10) { !engine.isPlaying }
        XCTAssertTrue(finished, "Трек длиной 1 с не доиграл за 10 с")
        try await Task.sleep(for: .seconds(2))

        XCTAssertEqual(engine.currentTrack?.id, short)
        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(engine.queue.entries.map(\.trackID), [short])
        XCTAssertEqual(engine.queue.currentIndex, 0)
    }
}
