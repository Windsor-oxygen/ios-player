import XCTest
@testable import Player

final class FileImporterTests: XCTestCase {
    private var locations: StorageLocations?

    override func setUpWithError() throws {
        locations = try TestSupport.makeLocations()
    }

    override func tearDown() {
        if let locations { TestSupport.cleanUp(locations) }
    }

    private func sourceURL(_ name: String) throws -> URL {
        try XCTUnwrap(locations).documents.deletingLastPathComponent().appending(path: "Source/\(name)")
    }

    func testCopiesPlayableFileIntoMusic() async throws {
        let locations = try XCTUnwrap(locations)
        let source = try TestSupport.write(TestSupport.wavData(), to: sourceURL("Song.wav"))
        let importer = FileImporter(locations: locations)

        let path = try await importer.importFile(source)

        XCTAssertEqual(path, "Music/Song.wav")
        XCTAssertTrue(FileManager.default.fileExists(atPath: locations.fileURL(forRelativePath: path).path(percentEncoded: false)))
        // Исходный файл не трогаем — это копия.
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path(percentEncoded: false)))
    }

    func testNameCollisionGetsSuffix() async throws {
        let locations = try XCTUnwrap(locations)
        let source = try TestSupport.write(TestSupport.wavData(), to: sourceURL("Song.wav"))
        let importer = FileImporter(locations: locations)

        let first = try await importer.importFile(source)
        let second = try await importer.importFile(source)
        let third = try await importer.importFile(source)

        XCTAssertEqual([first, second, third], ["Music/Song.wav", "Music/Song (2).wav", "Music/Song (3).wav"])
    }

    func testRejectsUnsupportedFormat() async throws {
        let source = try TestSupport.write(Data("OggS".utf8), to: sourceURL("Song.ogg"))
        let importer = FileImporter(locations: try XCTUnwrap(locations))
        do {
            _ = try await importer.importFile(source)
            XCTFail("ogg не должен импортироваться")
        } catch let error as ImportError {
            XCTAssertEqual(error, .unsupportedFormat("ogg"))
        }
    }

    func testRejectsNonAudio() async throws {
        let source = try TestSupport.write(Data("%PDF".utf8), to: sourceURL("Doc.pdf"))
        let importer = FileImporter(locations: try XCTUnwrap(locations))
        do {
            _ = try await importer.importFile(source)
            XCTFail("pdf не должен импортироваться")
        } catch let error as ImportError {
            XCTAssertEqual(error, .notAudio("Doc.pdf"))
        }
    }

    func testCorruptedFileIsRejectedAndNotLeftBehind() async throws {
        let locations = try XCTUnwrap(locations)
        let source = try TestSupport.write(Data("definitely not an mp4 container".utf8), to: sourceURL("Broken.m4a"))
        let importer = FileImporter(locations: locations)
        do {
            _ = try await importer.importFile(source)
            XCTFail("битый файл не должен импортироваться")
        } catch let error as ImportError {
            XCTAssertEqual(error, .unreadable)
        }
        XCTAssertTrue(FolderScanner.scan(locations).isEmpty)
        // Оригинал пользователя на месте.
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path(percentEncoded: false)))
    }

    func testBatchReportCollectsSuccessesAndFailures() async throws {
        let good = try TestSupport.write(TestSupport.wavData(), to: sourceURL("Good.wav"))
        let bad = try TestSupport.write(Data(), to: sourceURL("Bad.opus"))
        let report = await FileImporter(locations: try XCTUnwrap(locations)).importFiles([good, bad])
        XCTAssertEqual(report.importedPaths, ["Music/Good.wav"])
        XCTAssertEqual(report.failures, [.init(fileName: "Bad.opus", error: .unsupportedFormat("opus"))])
    }

    func testFileAlreadyInDocumentsIsNotCopied() async throws {
        let locations = try XCTUnwrap(locations)
        let inPlace = try TestSupport.write(TestSupport.wavData(), to: locations.documents.appending(path: "Own.wav"))
        let path = try await FileImporter(locations: locations).importFile(inPlace)
        XCTAssertEqual(path, "Own.wav")
        XCTAssertEqual(FolderScanner.scan(locations).count, 1)
    }

    func testDrainInboxMovesFilesAndSetsAsideTheRest() async throws {
        let locations = try XCTUnwrap(locations)
        try TestSupport.write(TestSupport.wavData(), to: locations.inbox.appending(path: "Shared.wav"))
        try TestSupport.write(Data("OggS".utf8), to: locations.inbox.appending(path: "Junk.ogg"))
        try TestSupport.write(Data("broken".utf8), to: locations.inbox.appending(path: "Broken.m4a"))

        let report = await FileImporter(locations: locations).drainInbox()

        XCTAssertEqual(report.importedPaths, ["Music/Shared.wav"])
        XCTAssertEqual(report.failures.count, 2)
        XCTAssertEqual(report.setAsideCount, 2)
        let fm = FileManager.default
        let leftovers = try fm.contentsOfDirectory(atPath: locations.inbox.path(percentEncoded: false))
        XCTAssertTrue(leftovers.isEmpty)
        // Ничего не удалено: неподходящие файлы отложены целиком, с тем же содержимым.
        let setAside = try fm.contentsOfDirectory(atPath: locations.notImported.path(percentEncoded: false))
        XCTAssertEqual(Set(setAside), ["Junk.ogg", "Broken.m4a"])
        let junk = try Data(contentsOf: locations.notImported.appending(path: "Junk.ogg"))
        XCTAssertEqual(junk, Data("OggS".utf8))
        // Отложенное не попадает в библиотеку.
        XCTAssertEqual(FolderScanner.scan(locations).map(\.relativePath), ["Music/Shared.wav"])
    }

    func testSanitizeFileName() {
        XCTAssertEqual(FileImporter.sanitize("a/b:c.mp3"), "a_b_c.mp3")
        XCTAssertEqual(FileImporter.sanitize("..hidden.mp3"), "hidden.mp3")
        XCTAssertEqual(FileImporter.sanitize("   "), "Track")
    }
}
