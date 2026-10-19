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

    func testCorruptedFileIsBackedUpAndLibraryStartsEmpty() async throws {
        let url = try XCTUnwrap(locations).libraryIndex
        try TestSupport.write(Data("{ not json".utf8), to: url)

        let outcome = await LibraryPersistence(fileURL: url).load()
        XCTAssertEqual(outcome, .recoveredFromCorruption)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        let backup = url.appendingPathExtension("corrupt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path(percentEncoded: false)))
    }
}
