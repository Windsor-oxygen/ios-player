import UIKit
import XCTest
@testable import Player

/// Обложки не пропадают: миниатюры пересоздаются из источника, ключ не затирается
/// ошибкой чтения, старый кэш переносится, потерянное в 1.0/1.1 возвращается один раз.
@MainActor
final class ArtworkRecoveryTests: XCTestCase {
    /// Считает обращения к тегам файлов.
    private actor Calls {
        private(set) var urls: [URL] = []
        func add(_ url: URL) { urls.append(url) }
    }

    private func imageData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        let image = renderer.image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        return image.pngData() ?? Data()
    }

    private func reader(returning result: ArtworkRead, calls: Calls) -> ArtworkReader {
        ArtworkReader { url in
            await calls.add(url)
            return result
        }
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let name = "PlayerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// Трек с файлом на диске (размер и дата совпадают — теги не перечитываются).
    private func installTrack(_ title: String, artworkKey: String?, at locations: StorageLocations) throws -> Track {
        let path = "Music/\(title).wav"
        let url = locations.fileURL(forRelativePath: path)
        let data = TestSupport.wavData()
        try TestSupport.write(data, to: url)
        let modified = try XCTUnwrap(url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        var track = TestSupport.track(title, path: path, size: Int64(data.count), modified: modified)
        track.artworkKey = artworkKey
        return track
    }

    private func saveIndex(_ tracks: [Track], at locations: StorageLocations) async throws {
        try await LibraryPersistence(fileURL: locations.libraryIndex).save(LibraryIndex(tracks: tracks))
    }

    func testMissingThumbnailsAreRebuiltFromTags() async throws {
        let locations = try TestSupport.makeLocations()
        defer { TestSupport.cleanUp(locations) }
        let data = imageData()
        // Ключ — хэш картинки; самих миниатюр нет (кэш очищен системой).
        let key = try XCTUnwrap(ArtworkStore(directory: locations.artwork).store(imageData: data))
        try FileManager.default.removeItem(at: locations.artwork)
        let track = try installTrack("Song", artworkKey: key, at: locations)
        try await saveIndex([track], at: locations)

        // Разовое восстановление уже выполнено — проверяем восстановление по запросу.
        let defaults = try isolatedDefaults()
        defaults.set(1, forKey: "library.artworkRecovery")
        let calls = Calls()
        let library = LibraryStore(locations: locations, defaults: defaults,
                                   artworkReader: reader(returning: .found(data), calls: calls))
        await library.refresh()
        XCTAssertFalse(library.artwork.hasImages(key: key))

        let image = await library.artworkImage(key: key, size: .small)
        XCTAssertNotNil(image)
        XCTAssertTrue(library.artwork.hasImages(key: key))
        XCTAssertEqual(library.tracksByID[track.id]?.artworkKey, key)
    }

    func testUnreadableFileKeepsArtworkAndTags() async throws {
        let locations = try TestSupport.makeLocations()
        defer { TestSupport.cleanUp(locations) }
        // Файл «изменился» (размер не совпадает), но прочитать его нельзя.
        let url = locations.fileURL(forRelativePath: "Music/Broken.m4a")
        try TestSupport.write(Data("not an mp4".utf8), to: url)
        var track = TestSupport.track("Старое название", path: "Music/Broken.m4a", artist: "Исполнитель", size: 1)
        track.artworkKey = "feedface"
        try await saveIndex([track], at: locations)

        let library = LibraryStore(locations: locations, defaults: try isolatedDefaults(),
                                   artworkReader: reader(returning: .failed, calls: Calls()))
        await library.refresh()
        await library.waitForArtworkRecovery()

        let reloaded = try XCTUnwrap(library.tracksByID[track.id])
        XCTAssertEqual(reloaded.artworkKey, "feedface")
        XCTAssertEqual(reloaded.title, "Старое название")
        XCTAssertEqual(reloaded.artist, "Исполнитель")
        XCTAssertTrue(reloaded.isUnplayable)
    }

    func testLegacyCachesArtworkIsMigrated() async throws {
        let locations = try TestSupport.makeLocations()
        defer { TestSupport.cleanUp(locations) }
        let key = try XCTUnwrap(ArtworkStore(directory: locations.legacyArtwork).store(imageData: imageData()))
        let track = try installTrack("Song", artworkKey: key, at: locations)
        try await saveIndex([track], at: locations)

        let calls = Calls()
        let library = LibraryStore(locations: locations, defaults: try isolatedDefaults(),
                                   artworkReader: reader(returning: .absent, calls: calls))
        await library.refresh()
        await library.waitForArtworkRecovery()

        XCTAssertTrue(library.artwork.hasImages(key: key))
        XCTAssertFalse(FileManager.default.fileExists(atPath: locations.legacyArtwork.path(percentEncoded: false)))
        let excluded = try locations.artwork.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        XCTAssertEqual(excluded, true)
        XCTAssertEqual(library.tracksByID[track.id]?.artworkKey, key)
        // Миниатюры на месте — тегов не читали.
        let read = await calls.urls
        XCTAssertTrue(read.isEmpty)
    }

    func testLostArtworkIsRecoveredOnceAndCustomArtworkIsSkipped() async throws {
        let locations = try TestSupport.makeLocations()
        defer { TestSupport.cleanUp(locations) }
        let lost = try installTrack("Lost", artworkKey: nil, at: locations)
        var custom = try installTrack("Custom", artworkKey: nil, at: locations)
        custom.customArtworkKey = "custom-key"
        custom.customArtworkPath = "CustomArtwork/\(custom.id.uuidString).jpg"
        try await saveIndex([lost, custom], at: locations)
        let defaults = try isolatedDefaults()
        let data = imageData()

        let calls = Calls()
        let library = LibraryStore(locations: locations, defaults: defaults,
                                   artworkReader: reader(returning: .found(data), calls: calls))
        await library.refresh()
        await library.waitForArtworkRecovery()

        let recoveredKey = try XCTUnwrap(library.tracksByID[lost.id]?.artworkKey)
        XCTAssertTrue(library.artwork.hasImages(key: recoveredKey))
        XCTAssertNil(library.tracksByID[custom.id]?.artworkKey)
        let read = await calls.urls
        XCTAssertEqual(read.map(\.lastPathComponent), ["Lost.wav"])
        // Результат сохранён в Library.json.
        await library.saveNow()
        guard case .loaded(let saved) = await LibraryPersistence(fileURL: locations.libraryIndex).load() else {
            return XCTFail("Индекс не читается")
        }
        XCTAssertEqual(saved.tracks.first { $0.id == lost.id }?.artworkKey, recoveredKey)

        // Второй запуск — восстановление уже выполнено.
        let secondCalls = Calls()
        let second = LibraryStore(locations: locations, defaults: defaults,
                                  artworkReader: reader(returning: .found(data), calls: secondCalls))
        await second.refresh()
        await second.waitForArtworkRecovery()
        let secondRead = await secondCalls.urls
        XCTAssertTrue(secondRead.isEmpty)
    }

    func testPlaceholderIsStablePerID() {
        let id = UUID().uuidString
        XCTAssertEqual(DS.Palette.placeholderSymbol(for: id), DS.Palette.placeholderSymbol(for: id))
        XCTAssertEqual(DS.Palette.placeholderPair(for: id).0, DS.Palette.placeholderPair(for: id).0)
        let symbols = Set((0..<64).map { _ in DS.Palette.placeholderSymbol(for: UUID().uuidString) })
        XCTAssertGreaterThan(symbols.count, DS.Palette.placeholderSymbols.count / 2)
        for symbol in DS.Palette.placeholderSymbols {
            XCTAssertNotNil(UIImage(systemName: symbol), "Нет SF Symbol \(symbol)")
        }
    }
}
