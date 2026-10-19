import XCTest
@testable import Player

/// Установка новой версии поверх старой: в контейнере уже лежат музыка,
/// Library.json, Playback.json и настройки в формате v1.0. После запуска
/// библиотека, плейлисты, очередь и настройки должны восстановиться без потерь.
@MainActor
final class UpgradeScenarioTests: XCTestCase {
    func testExistingInstallRestoresWithoutLoss() async throws {
        let locations = try TestSupport.makeLocations()
        defer { TestSupport.cleanUp(locations) }
        let original = try JSONDecoder().decode(LibraryIndex.self, from: Fixtures.data("Library-v1"))
        try installV1Container(original, at: locations)

        let library = LibraryStore(locations: locations)
        await library.refresh()

        XCTAssertNil(library.notice)
        XCTAssertNil(library.lastReport)
        // Те же треки, в том же порядке, без дублей и без потери тегов.
        XCTAssertEqual(library.tracks, original.tracks)
        XCTAssertEqual(library.playlists, original.playlists)
        XCTAssertTrue(library.tracksByID[Fixtures.trackMissing]?.isMissing ?? false)

        // Сохранённое новой версией снова читается и ничего не теряет.
        await library.saveNow()
        guard case .loaded(let saved) = await LibraryPersistence(fileURL: locations.libraryIndex).load() else {
            return XCTFail("Индекс после сохранения не читается")
        }
        XCTAssertEqual(saved.tracks, original.tracks)
        XCTAssertEqual(saved.playlists, original.playlists)

        // Очередь и позиция.
        let loadedSnapshot = await PlaybackSnapshotStore(fileURL: locations.playbackState).load()
        let snapshot = try XCTUnwrap(loadedSnapshot)
        XCTAssertEqual(snapshot.queue.current?.trackID, Fixtures.trackA)
        XCTAssertEqual(snapshot.position, 42.5)
        for entry in snapshot.queue.entries {
            XCTAssertNotNil(library.tracksByID[entry.trackID], "Трек очереди не найден в библиотеке")
        }

        // Настройки.
        let settings = AppSettings(defaults: try Fixtures.defaults(from: "Settings-v1"))
        XCTAssertEqual(settings.appearance, .light)
        XCTAssertEqual(settings.skipInterval, 30)
        XCTAssertEqual(settings.lockScreenControls, .skip)
    }

    func testNewFilesAddedWhileOldVersionWasInstalledAreAppended() async throws {
        let locations = try TestSupport.makeLocations()
        defer { TestSupport.cleanUp(locations) }
        let original = try JSONDecoder().decode(LibraryIndex.self, from: Fixtures.data("Library-v1"))
        try installV1Container(original, at: locations)
        try TestSupport.write(TestSupport.wavData(), to: locations.music.appending(path: "Новая.wav"))

        let library = LibraryStore(locations: locations)
        await library.refresh()

        XCTAssertEqual(Array(library.tracks.prefix(original.tracks.count)).map(\.id), original.tracks.map(\.id))
        XCTAssertEqual(library.tracks.count, original.tracks.count + 1)
        XCTAssertEqual(library.playlists, original.playlists)
    }

    func testCorruptedIndexIsRebuiltFromMusicFolder() async throws {
        let locations = try TestSupport.makeLocations()
        defer { TestSupport.cleanUp(locations) }
        let original = try JSONDecoder().decode(LibraryIndex.self, from: Fixtures.data("Library-v1"))
        try installV1Container(original, at: locations)
        try TestSupport.write(Data("{\"version\":1,\"tracks\":[".utf8), to: locations.libraryIndex)

        let library = LibraryStore(locations: locations)
        await library.refresh()

        XCTAssertNotNil(library.notice)
        // Все файлы на месте и найдены заново сканированием папки.
        let available = original.tracks.filter { !$0.isMissing }
        XCTAssertEqual(Set(library.tracks.map(\.relativePath)), Set(available.map(\.relativePath)))
        for track in available {
            let path = locations.fileURL(forRelativePath: track.relativePath).path(percentEncoded: false)
            XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        }
    }

    /// Файлы музыки с теми же размером и датой изменения, что записаны в индексе,
    /// плюс Library.json и Playback.json в формате v1.0.
    private func installV1Container(_ index: LibraryIndex, at locations: StorageLocations) throws {
        for track in index.tracks where !track.isMissing {
            let url = locations.fileURL(forRelativePath: track.relativePath)
            let data = TestSupport.wavData()
            XCTAssertEqual(Int64(data.count), track.fileSize, "Размер фикстуры должен совпадать с файлом")
            try TestSupport.write(data, to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: track.modificationDate], ofItemAtPath: url.path(percentEncoded: false)
            )
        }
        try TestSupport.write(Fixtures.data("Library-v1"), to: locations.libraryIndex)
        try TestSupport.write(Fixtures.data("Playback-v1"), to: locations.playbackState)
    }
}
