import XCTest
@testable import Player

final class LibraryReconcilerTests: XCTestCase {
    private let mtime = Date(timeIntervalSinceReferenceDate: 1000)

    private func file(_ path: String, size: Int64 = 100, modified: Date? = nil) -> ScannedFile {
        ScannedFile(relativePath: path, fileSize: size, modificationDate: modified ?? mtime)
    }

    func testEmptyLibraryAndEmptyDisk() {
        let result = LibraryReconciler.reconcile(existing: [], scanned: [])
        XCTAssertTrue(result.tracks.isEmpty)
        XCTAssertEqual(result.addedCount, 0)
        XCTAssertEqual(result.missingCount, 0)
    }

    func testAddsNewFilesWithFileNameAsTitle() throws {
        let result = LibraryReconciler.reconcile(existing: [], scanned: [file("Music/My Song.mp3")])
        XCTAssertEqual(result.addedCount, 1)
        let track = try XCTUnwrap(result.tracks.first)
        XCTAssertEqual(track.title, "My Song")
        XCTAssertTrue(track.needsMetadata)
        XCTAssertFalse(track.isMissing)
    }

    func testKeepsIdentityOfExistingTracks() {
        let existing = TestSupport.track("A", path: "Music/A.mp3")
        let result = LibraryReconciler.reconcile(existing: [existing], scanned: [file("Music/A.mp3")])
        XCTAssertEqual(result.tracks, [existing])
        XCTAssertEqual(result.addedCount, 0)
    }

    func testMarksDeletedFilesAsMissingInsteadOfDropping() throws {
        let existing = TestSupport.track("A", path: "Music/A.mp3")
        let result = LibraryReconciler.reconcile(existing: [existing], scanned: [])
        XCTAssertEqual(result.missingCount, 1)
        let track = try XCTUnwrap(result.tracks.first)
        XCTAssertEqual(track.id, existing.id)
        XCTAssertTrue(track.isMissing)
    }

    func testFileReturningClearsMissingFlag() throws {
        var existing = TestSupport.track("A", path: "Music/A.mp3")
        existing.isMissing = true
        let result = LibraryReconciler.reconcile(existing: [existing], scanned: [file("Music/A.mp3")])
        let track = try XCTUnwrap(result.tracks.first)
        XCTAssertFalse(track.isMissing)
        XCTAssertFalse(track.needsMetadata)
    }

    func testChangedFileNeedsMetadataAgain() throws {
        var existing = TestSupport.track("A", path: "Music/A.mp3")
        existing.isUnplayable = true
        let result = LibraryReconciler.reconcile(existing: [existing], scanned: [file("Music/A.mp3", size: 999)])
        let track = try XCTUnwrap(result.tracks.first)
        XCTAssertTrue(track.needsMetadata)
        XCTAssertFalse(track.isUnplayable)
        XCTAssertEqual(track.fileSize, 999)
    }

    func testSubSecondTimestampDifferenceIsIgnored() throws {
        let existing = TestSupport.track("A", path: "Music/A.mp3")
        let result = LibraryReconciler.reconcile(
            existing: [existing],
            scanned: [file("Music/A.mp3", modified: mtime.addingTimeInterval(0.4))]
        )
        XCTAssertFalse(try XCTUnwrap(result.tracks.first).needsMetadata)
    }

    func testDropsDuplicatePaths() {
        let first = TestSupport.track("A", path: "Music/A.mp3")
        let duplicate = TestSupport.track("A copy", path: "Music/A.mp3")
        let result = LibraryReconciler.reconcile(existing: [first, duplicate], scanned: [file("Music/A.mp3")])
        XCTAssertEqual(result.tracks.map(\.id), [first.id])
    }

    func testLargeLibrary() {
        let scanned = (0..<1500).map { file("Music/Track \($0).mp3") }
        let initial = LibraryReconciler.reconcile(existing: [], scanned: scanned)
        XCTAssertEqual(initial.tracks.count, 1500)
        let again = LibraryReconciler.reconcile(existing: initial.tracks, scanned: scanned.shuffled())
        XCTAssertEqual(again.tracks, initial.tracks)
        XCTAssertEqual(again.addedCount, 0)
    }
}
