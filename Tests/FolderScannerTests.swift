import XCTest
@testable import Player

final class FolderScannerTests: XCTestCase {
    private var locations: StorageLocations?

    override func setUpWithError() throws {
        locations = try TestSupport.makeLocations()
    }

    override func tearDown() {
        if let locations { TestSupport.cleanUp(locations) }
    }

    func testFindsSupportedFilesRecursivelyAndSkipsTheRest() throws {
        let locations = try XCTUnwrap(locations)
        let docs = locations.documents
        let bytes = Data("x".utf8)
        try TestSupport.write(bytes, to: docs.appending(path: "Root.mp3"))
        try TestSupport.write(bytes, to: docs.appending(path: "Music/Album/One.flac"))
        try TestSupport.write(bytes, to: docs.appending(path: "Music/Two.M4A"))
        try TestSupport.write(bytes, to: docs.appending(path: "Music/cover.jpg"))
        try TestSupport.write(bytes, to: docs.appending(path: "Music/bad.ogg"))
        try TestSupport.write(bytes, to: docs.appending(path: "Music/.hidden.mp3"))
        try TestSupport.write(bytes, to: docs.appending(path: "Inbox/Pending.mp3"))
        try TestSupport.write(bytes, to: locations.notImported.appending(path: "Broken.mp3"))

        let paths = Set(FolderScanner.scan(locations).map(\.relativePath))
        XCTAssertEqual(paths, ["Root.mp3", "Music/Album/One.flac", "Music/Two.M4A"])
    }

    func testEmptyFolder() throws {
        XCTAssertTrue(FolderScanner.scan(try XCTUnwrap(locations)).isEmpty)
    }

    func testRelativePathRoundTrip() throws {
        let locations = try XCTUnwrap(locations)
        let url = locations.fileURL(forRelativePath: "Music/Песня (2).mp3")
        XCTAssertEqual(locations.relativePath(of: url), "Music/Песня (2).mp3")
        XCTAssertNil(locations.relativePath(of: URL(filePath: "/tmp/elsewhere.mp3")))
    }
}
