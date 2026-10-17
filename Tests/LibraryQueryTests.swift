import XCTest
@testable import Player

final class LibraryQueryTests: XCTestCase {
    func testTitleSortIsNaturalAndLocalized() {
        let latin = ["Song 10", "song 2", "Banana"].map { TestSupport.track($0) }
        XCTAssertEqual(LibraryQuery.sortedSongs(latin, by: .title).map(\.title), ["Banana", "song 2", "Song 10"])
        // Порядок между алфавитами зависит от локали устройства, поэтому проверяем их по отдельности.
        let cyrillic = ["Яблоко", "арбуз", "Ёж"].map { TestSupport.track($0) }
        XCTAssertEqual(LibraryQuery.sortedSongs(cyrillic, by: .title).map(\.title), ["арбуз", "Ёж", "Яблоко"])
    }

    func testDateAddedSortNewestFirst() {
        let old = TestSupport.track("Old", dateAdded: Date(timeIntervalSinceReferenceDate: 10))
        let new = TestSupport.track("New", dateAdded: Date(timeIntervalSinceReferenceDate: 20))
        XCTAssertEqual(LibraryQuery.sortedSongs([old, new], by: .dateAdded).map(\.title), ["New", "Old"])
    }

    func testFilterMatchesAllTokensAcrossFields() {
        let tracks = [
            TestSupport.track("Yesterday", artist: "The Beatles", album: "Help!"),
            TestSupport.track("Help", artist: "Someone"),
            TestSupport.track("Кино", artist: "Цой", album: "Группа крови"),
        ]
        XCTAssertEqual(LibraryQuery.filter(tracks, query: "beatles help").map(\.title), ["Yesterday"])
        XCTAssertEqual(LibraryQuery.filter(tracks, query: "ЦОЙ").map(\.title), ["Кино"])
        XCTAssertEqual(LibraryQuery.filter(tracks, query: "  ").count, 3)
        XCTAssertTrue(LibraryQuery.filter(tracks, query: "nothing").isEmpty)
    }

    func testAlbumsGroupCaseInsensitivelyAndOrderByTrackNumber() throws {
        let tracks = [
            TestSupport.track("Third", artist: "Band", album: "Record", trackNumber: 3),
            TestSupport.track("First", artist: "band", album: "record", trackNumber: 1),
            TestSupport.track("Second", artist: "Band", album: "Record", trackNumber: 2),
            TestSupport.track("Other", artist: "Band", album: "Another"),
        ]
        let albums = LibraryQuery.albums(from: tracks)
        XCTAssertEqual(albums.count, 2)
        let record = try XCTUnwrap(albums.first { $0.title.lowercased() == "record" })
        let byID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0.title) })
        XCTAssertEqual(record.trackIDs.compactMap { byID[$0] }, ["First", "Second", "Third"])
    }

    func testAlbumOrderUsesDiscThenTrack() {
        let a = TestSupport.track("A", trackNumber: 2, discNumber: 1)
        let b = TestSupport.track("B", trackNumber: 1, discNumber: 2)
        let c = TestSupport.track("C", trackNumber: nil, discNumber: 1)
        let sorted = [b, c, a].sorted(by: LibraryQuery.albumOrder).map(\.title)
        XCTAssertEqual(sorted, ["A", "C", "B"])
    }

    func testArtistsIncludeUnknown() throws {
        let tracks = [
            TestSupport.track("X", artist: nil),
            TestSupport.track("Y", artist: "Artist", album: "One"),
            TestSupport.track("Z", artist: "Artist", album: "Two"),
        ]
        let artists = LibraryQuery.artists(from: tracks)
        XCTAssertEqual(artists.count, 2)
        let artist = try XCTUnwrap(artists.first { $0.name == "Artist" })
        XCTAssertEqual(artist.trackIDs.count, 2)
        XCTAssertEqual(artist.albumIDs.count, 2)
        XCTAssertTrue(artists.contains { $0.name == LibraryQuery.unknownArtist })
    }

    func testTrackNumberParsing() {
        XCTAssertEqual(MetadataLoader.parseTrackNumber("3"), 3)
        XCTAssertEqual(MetadataLoader.parseTrackNumber("03/12"), 3)
        XCTAssertEqual(MetadataLoader.parseTrackNumber(" 7 / 9"), 7)
        XCTAssertNil(MetadataLoader.parseTrackNumber("0"))
        XCTAssertNil(MetadataLoader.parseTrackNumber("abc"))
    }

    func testLargeLibraryGroupingIsFast() {
        let tracks = (0..<2000).map { i in
            TestSupport.track("Track \(i)", artist: "Artist \(i % 50)", album: "Album \(i % 200)", trackNumber: i % 12 + 1)
        }
        measure {
            _ = LibraryQuery.albums(from: tracks)
            _ = LibraryQuery.sortedSongs(tracks, by: .title)
        }
    }
}
