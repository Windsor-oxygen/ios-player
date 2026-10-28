import ImageIO
import UIKit
import XCTest
@testable import Player

/// Своя обложка: хранение относительным путём, приоритет, сброс, альбом,
/// удаление вместе с треком; обрезка и уменьшение до 1000×1000.
@MainActor
final class CustomArtworkTests: XCTestCase {
    private func image(width: Int, height: Int) -> CGImage? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height),
                                               format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        return renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }.cgImage
    }

    private func pixelSize(of jpeg: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return CGSize(width: image.width, height: image.height)
    }

    private func makeLibrary(_ locations: StorageLocations, tracks: [Track]) async throws -> LibraryStore {
        try await LibraryPersistence(fileURL: locations.libraryIndex).save(LibraryIndex(tracks: tracks))
        let name = "PlayerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.set(1, forKey: "library.artworkRecovery")
        let library = LibraryStore(locations: locations, defaults: defaults,
                                   artworkReader: ArtworkReader { _ in .absent })
        await library.ensureLoaded()
        return library
    }

    private func jpeg() throws -> Data {
        let cgImage = try XCTUnwrap(image(width: 1200, height: 1200))
        return try XCTUnwrap(ArtworkEditing.render(cgImage, crop: CGRect(x: 0, y: 0, width: 1200, height: 1200)))
    }

    func testSetCustomArtworkStoresRelativePathAndTakesPriority() async throws {
        let locations = try TestSupport.makeLocations()
        defer { TestSupport.cleanUp(locations) }
        var track = TestSupport.track("Song")
        track.artworkKey = "embedded"
        let library = try await makeLibrary(locations, tracks: [track])

        try await library.setCustomArtwork(try jpeg(), for: [track.id])

        let updated = try XCTUnwrap(library.tracksByID[track.id])
        XCTAssertEqual(updated.customArtworkPath, "CustomArtwork/\(track.id.uuidString).jpg")
        XCTAssertFalse(updated.customArtworkPath?.hasPrefix("/") ?? true, "Путь должен быть относительным")
        let key = try XCTUnwrap(updated.customArtworkKey)
        XCTAssertEqual(updated.displayArtworkKey, key, "Своя обложка важнее обложки из файла")
        XCTAssertEqual(updated.artworkKey, "embedded", "Обложка из файла сохраняется для сброса")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: locations.supportURL(forRelativePath: StorageLocations.customArtworkPath(for: track.id)).path(percentEncoded: false)))
        XCTAssertTrue(library.artwork.hasImages(key: key))

        // Сохранилось в Library.json.
        await library.saveNow()
        guard case .loaded(let saved) = await LibraryPersistence(fileURL: locations.libraryIndex).load() else {
            return XCTFail("Индекс не читается")
        }
        XCTAssertEqual(saved.tracks.first?.customArtworkKey, key)
    }

    func testResetReturnsToEmbeddedOrPlaceholder() async throws {
        let locations = try TestSupport.makeLocations()
        defer { TestSupport.cleanUp(locations) }
        var withEmbedded = TestSupport.track("A")
        withEmbedded.artworkKey = "embedded"
        let withoutArtwork = TestSupport.track("B")
        let library = try await makeLibrary(locations, tracks: [withEmbedded, withoutArtwork])
        try await library.setCustomArtwork(try jpeg(), for: [withEmbedded.id, withoutArtwork.id])

        await library.resetCustomArtwork(for: [withEmbedded.id, withoutArtwork.id])

        XCTAssertEqual(library.tracksByID[withEmbedded.id]?.displayArtworkKey, "embedded")
        XCTAssertNil(library.tracksByID[withoutArtwork.id]?.displayArtworkKey, "Без обложки — заглушка")
        for id in [withEmbedded.id, withoutArtwork.id] {
            let path = locations.supportURL(forRelativePath: StorageLocations.customArtworkPath(for: id))
            XCTAssertFalse(FileManager.default.fileExists(atPath: path.path(percentEncoded: false)))
        }
    }

    func testAlbumArtworkSharesThumbnails() async throws {
        let locations = try TestSupport.makeLocations()
        defer { TestSupport.cleanUp(locations) }
        let tracks = [TestSupport.track("1", album: "Альбом"), TestSupport.track("2", album: "Альбом")]
        let library = try await makeLibrary(locations, tracks: tracks)

        try await library.setCustomArtwork(try jpeg(), for: tracks.map(\.id))

        let keys = Set(tracks.compactMap { library.tracksByID[$0.id]?.customArtworkKey })
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(library.albums.first?.artworkKey, keys.first)
    }

    func testDeletingTrackRemovesItsCustomArtworkOnly() async throws {
        let locations = try TestSupport.makeLocations()
        defer { TestSupport.cleanUp(locations) }
        let audio = try TestSupport.write(TestSupport.wavData(), to: locations.fileURL(forRelativePath: "Music/Song.mp3"))
        let track = TestSupport.track("Song", path: "Music/Song.mp3")
        let library = try await makeLibrary(locations, tracks: [track])
        try await library.setCustomArtwork(try jpeg(), for: [track.id])
        let custom = locations.supportURL(forRelativePath: StorageLocations.customArtworkPath(for: track.id))

        await library.delete([track.id])

        XCTAssertFalse(FileManager.default.fileExists(atPath: custom.path(percentEncoded: false)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path(percentEncoded: false)))
    }

    func testCustomArtworkThumbnailsAreRebuiltFromSavedFile() async throws {
        let locations = try TestSupport.makeLocations()
        defer { TestSupport.cleanUp(locations) }
        let track = TestSupport.track("Song")
        let library = try await makeLibrary(locations, tracks: [track])
        try await library.setCustomArtwork(try jpeg(), for: [track.id])
        let key = try XCTUnwrap(library.tracksByID[track.id]?.customArtworkKey)
        // Миниатюры пропали — источник своей обложки остаётся в CustomArtwork.
        try FileManager.default.removeItem(at: locations.artwork)

        let image = await library.artworkImage(key: key, size: .small)
        XCTAssertNotNil(image)
    }

    // MARK: - Обрезка

    func testRenderCropsAndScalesDownTo1000() throws {
        let big = try XCTUnwrap(image(width: 2400, height: 1600))
        let data = try XCTUnwrap(ArtworkEditing.render(big, crop: CGRect(x: 400, y: 0, width: 1600, height: 1600)))
        XCTAssertEqual(pixelSize(of: data), CGSize(width: 1000, height: 1000))
    }

    func testRenderDoesNotUpscaleSmallImages() throws {
        let small = try XCTUnwrap(image(width: 300, height: 300))
        let data = try XCTUnwrap(ArtworkEditing.render(small, crop: CGRect(x: 0, y: 0, width: 300, height: 300)))
        XCTAssertEqual(pixelSize(of: data), CGSize(width: 300, height: 300))
    }

    func testCropRectFollowsZoomAndOffset() {
        let size = CGSize(width: 2000, height: 1000)
        // Без масштаба — центральный квадрат по короткой стороне.
        XCTAssertEqual(ArtworkEditing.cropRect(imageSize: size, viewSide: 100, zoom: 1, offset: .zero),
                       CGRect(x: 500, y: 0, width: 1000, height: 1000))
        // Сдвиг вправо до упора показывает левый край.
        XCTAssertEqual(ArtworkEditing.cropRect(imageSize: size, viewSide: 100, zoom: 1, offset: CGSize(width: 500, height: 0)),
                       CGRect(x: 0, y: 0, width: 1000, height: 1000))
        // Двукратное увеличение — квадрат вдвое меньше, по центру.
        XCTAssertEqual(ArtworkEditing.cropRect(imageSize: size, viewSide: 100, zoom: 2, offset: .zero),
                       CGRect(x: 750, y: 250, width: 500, height: 500))
    }

    func testOffsetIsClampedToImageEdges() {
        let clamped = ArtworkEditing.clampedOffset(CGSize(width: 9999, height: 9999),
                                                   imageSize: CGSize(width: 2000, height: 1000), viewSide: 100, zoom: 1)
        XCTAssertEqual(clamped, CGSize(width: 50, height: 0))
    }
}
