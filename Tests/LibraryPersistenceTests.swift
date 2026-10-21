import XCTest
@testable import Player

final class LibraryPersistenceTests: XCTestCase {
    private var locations: StorageLocations?

    override func setUpWithError() throws {
        locations = try TestSupport.makeLocations()
    }

    override func tearDown() {
        if let locations { TestSupport.cleanUp(locations) }
    }

    func testMissingFileLoadsAsEmpty() async throws {
        let persistence = LibraryPersistence(fileURL: try XCTUnwrap(locations).libraryIndex)
        let outcome = await persistence.load()
        XCTAssertEqual(outcome, .empty)
    }

    func testRoundTrip() async throws {
        let url = try XCTUnwrap(locations).libraryIndex
        let tracks = [
            TestSupport.track("Один", artist: "Исполнитель", album: "Альбом", trackNumber: 1),
            TestSupport.track("Two", path: "Music/Sub/Two.flac"),
        ]
        let index = LibraryIndex(tracks: tracks, playlists: [Playlist(name: "Любимое", trackIDs: tracks.map(\.id))])
        let persistence = LibraryPersistence(fileURL: url)
        try await persistence.save(index)

        let reloaded = await LibraryPersistence(fileURL: url).load()
        XCTAssertEqual(reloaded, .loaded(index))
    }

    func testSaveOverwritesAtomically() async throws {
        let url = try XCTUnwrap(locations).libraryIndex
        let persistence = LibraryPersistence(fileURL: url)
        try await persistence.save(LibraryIndex(tracks: [TestSupport.track("A")]))
        let second = LibraryIndex(tracks: [TestSupport.track("B"), TestSupport.track("C")])
        try await persistence.save(second)
        let outcome = await persistence.load()
        XCTAssertEqual(outcome, .loaded(second))
    }

    func testCorruptedFileIsCopiedNeverMovedOrDeleted() async throws {
        let url = try XCTUnwrap(locations).libraryIndex
        let garbage = Data("{ not json".utf8)
        try TestSupport.write(garbage, to: url)

        let first = await LibraryPersistence(fileURL: url).load()
        XCTAssertEqual(first, .recovered(LibraryIndex(), backupCreated: true))
        // Исходник на месте и не изменён.
        XCTAssertEqual(try Data(contentsOf: url), garbage)
        XCTAssertEqual(try backups(of: url).count, 1)

        // Второй сбой не затирает первую копию.
        _ = await LibraryPersistence(fileURL: url).load()
        let copies = try backups(of: url)
        XCTAssertEqual(copies.count, 2)
        for copy in copies {
            XCTAssertEqual(try Data(contentsOf: copy), garbage)
        }
    }

    func testDamagedTrackAndPlaylistAreSalvaged() async throws {
        let url = try XCTUnwrap(locations).libraryIndex
        var json = try XCTUnwrap(String(data: Fixtures.data("Library-v1"), encoding: .utf8))
        // Портим поле одного трека и один ID в плейлисте.
        json = json.replacingOccurrences(of: "\"duration\" : 187", with: "\"duration\" : \"сломано\"")
        json = json.replacingOccurrences(of: "\"createdAt\" : 782000100", with: "\"createdAt\" : null")
        try TestSupport.write(Data(json.utf8), to: url)

        let outcome = await LibraryPersistence(fileURL: url).load()
        guard case .recovered(let index, let backupCreated) = outcome else {
            return XCTFail("Ожидалось восстановление, получено \(outcome)")
        }
        XCTAssertTrue(backupCreated)
        XCTAssertEqual(index.tracks.map(\.id), [Fixtures.trackA, Fixtures.trackB, Fixtures.trackC, Fixtures.trackMissing])
        let salvaged = index.tracks[1]
        XCTAssertEqual(salvaged.relativePath, "Music/Альбом/02 Second Song.wav")
        XCTAssertTrue(salvaged.needsMetadata)
        XCTAssertEqual(index.playlists.map(\.name), ["Любимое", "Пустой"])
        XCTAssertEqual(index.playlists[0].trackIDs, [Fixtures.trackC, Fixtures.trackA, Fixtures.trackC])
    }

    func testUnreadableIndexIsNeverOverwritten() async throws {
        let url = try XCTUnwrap(locations).libraryIndex
        // Папка вместо файла: существует, но не читается как данные.
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let persistence = LibraryPersistence(fileURL: url)

        let outcome = await persistence.load()
        XCTAssertEqual(outcome, .unreadable)
        do {
            try await persistence.save(LibraryIndex())
            XCTFail("Запись должна быть заблокирована")
        } catch LibraryPersistence.SaveError.writeProtected {}
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testIndexFromNewerVersionIsBackedUpBeforeFirstSave() async throws {
        let url = try XCTUnwrap(locations).libraryIndex
        let original = try JSONEncoder().encode(LibraryIndex(version: LibraryIndex.currentVersion + 1, tracks: [TestSupport.track("A")]))
        try TestSupport.write(original, to: url)
        let persistence = LibraryPersistence(fileURL: url)
        guard case .loaded = await persistence.load() else { return XCTFail("Файл должен читаться") }
        XCTAssertTrue(try backups(of: url).isEmpty)

        try await persistence.save(LibraryIndex())
        let copies = try backups(of: url)
        XCTAssertEqual(copies.count, 1)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(copies.first)), original)
    }

    func testCorruptedPlaybackStateIsCopiedBeforeReset() async throws {
        let url = try XCTUnwrap(locations).playbackState
        try TestSupport.write(Data("[]".utf8), to: url)
        let store = PlaybackSnapshotStore(fileURL: url)
        let loaded = await store.load()
        XCTAssertNil(loaded)
        XCTAssertEqual(try backups(of: url).count, 1)
    }

    private func backups(of url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(url.lastPathComponent + ".backup-") }
    }
}
