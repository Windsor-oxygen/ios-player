import XCTest
@testable import Player

/// Файлы в формате версии 1.0 (Tests/Fixtures) должны читаться без потерь.
/// Фикстуры сняты с кода v1.0: повторное кодирование даёт ровно тот же JSON,
/// поэтому любое несовместимое изменение моделей уронит эти тесты.
final class UpgradeCompatibilityTests: XCTestCase {
    func testLibraryV1Decodes() throws {
        let index = try JSONDecoder().decode(LibraryIndex.self, from: Fixtures.data("Library-v1"))
        XCTAssertEqual(index.version, 1)
        XCTAssertEqual(index.tracks.map(\.id), [Fixtures.trackA, Fixtures.trackB, Fixtures.trackC, Fixtures.trackMissing])

        let first = index.tracks[0]
        XCTAssertEqual(first.relativePath, "Music/Северное сияние.wav")
        XCTAssertEqual(first.title, "Северное сияние")
        XCTAssertEqual(first.artist, "Полярный экспресс")
        XCTAssertEqual(first.album, "Зима")
        XCTAssertEqual(first.trackNumber, 1)
        XCTAssertEqual(first.discNumber, 1)
        XCTAssertEqual(first.duration, 215.5)
        XCTAssertEqual(first.fileSize, 8044)
        XCTAssertEqual(first.modificationDate, Date(timeIntervalSinceReferenceDate: 780_000_000))
        XCTAssertNotNil(first.artworkKey)
        XCTAssertFalse(first.needsMetadata)

        let untagged = index.tracks[2]
        XCTAssertNil(untagged.artist)
        XCTAssertNil(untagged.album)
        XCTAssertNil(untagged.trackNumber)
        XCTAssertTrue(index.tracks[3].isMissing)

        XCTAssertEqual(index.playlists.map(\.name), ["Любимое", "Пустой"])
        XCTAssertEqual(index.playlists[0].trackIDs, [Fixtures.trackC, Fixtures.trackA, Fixtures.trackC])
        XCTAssertTrue(index.playlists[1].trackIDs.isEmpty)
    }

    func testLibraryV1MatchesCurrentEncoding() throws {
        let data = try Fixtures.data("Library-v1")
        let index = try JSONDecoder().decode(LibraryIndex.self, from: data)
        try Fixtures.assertSameJSON(data, try JSONEncoder().encode(index))
    }

    func testPlaybackV1Decodes() throws {
        let snapshot = try JSONDecoder().decode(PlaybackSnapshot.self, from: Fixtures.data("Playback-v1"))
        XCTAssertEqual(snapshot.position, 42.5)
        XCTAssertEqual(snapshot.queue.current?.trackID, Fixtures.trackA)
        XCTAssertEqual(snapshot.queue.currentIndex, 1)
        XCTAssertTrue(snapshot.queue.isShuffled)
        XCTAssertEqual(snapshot.queue.repeatMode, .all)
        XCTAssertEqual(snapshot.queue.upcoming.map(\.trackID), [Fixtures.trackC])
    }

    func testPlaybackV1MatchesCurrentEncoding() throws {
        let data = try Fixtures.data("Playback-v1")
        let snapshot = try JSONDecoder().decode(PlaybackSnapshot.self, from: data)
        try Fixtures.assertSameJSON(data, try JSONEncoder().encode(snapshot))
    }
}

@MainActor
final class SettingsCompatibilityTests: XCTestCase {
    func testSettingsV1Restore() throws {
        let defaults = try Fixtures.defaults(from: "Settings-v1")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.appearance, .light)
        XCTAssertEqual(settings.skipInterval, 30)
        XCTAssertEqual(settings.lockScreenControls, .skip)
        XCTAssertEqual(defaults.string(forKey: "songs.sort").flatMap(SongSort.init(rawValue:)), .artist)
    }
}

/// Пути хранения и идентификатор приложения — от них зависит, найдёт ли
/// новая версия музыку и библиотеку, установленные старой. Менять нельзя.
final class StorageContractTests: XCTestCase {
    func testBundleIdentifierIsUnchanged() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "io.github.windsor-oxygen.player")
    }

    func testStoragePathsAreUnchanged() {
        let standard = StorageLocations.standard
        XCTAssertEqual(path(standard.documents), path(URL.documentsDirectory))
        XCTAssertEqual(path(standard.applicationSupport), path(URL.applicationSupportDirectory))
        XCTAssertEqual(path(standard.music), path(URL.documentsDirectory) + "/Music")
        XCTAssertEqual(path(standard.inbox), path(URL.documentsDirectory) + "/Inbox")
        XCTAssertEqual(path(standard.libraryIndex), path(URL.applicationSupportDirectory) + "/Library.json")
        XCTAssertEqual(path(standard.playbackState), path(URL.applicationSupportDirectory) + "/Playback.json")
    }

    private func path(_ url: URL) -> String {
        let value = url.standardizedFileURL.path(percentEncoded: false)
        return value.hasSuffix("/") ? String(value.dropLast()) : value
    }
}

/// Доступ к JSON-фикстурам из Tests/Fixtures.
enum Fixtures {
    static let trackA = uuid("11111111-1111-4111-8111-111111111111")
    static let trackB = uuid("22222222-2222-4222-8222-222222222222")
    static let trackC = uuid("33333333-3333-4333-8333-333333333333")
    static let trackMissing = uuid("44444444-4444-4444-8444-444444444444")

    static func data(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle(for: BundleToken.self).url(forResource: name, withExtension: "json"),
            "Нет фикстуры \(name).json"
        )
        return try Data(contentsOf: url)
    }

    /// Изолированный UserDefaults с ключами из фикстуры.
    static func defaults(from name: String) throws -> UserDefaults {
        let suite = "PlayerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: data(name)) as? [String: Any])
        for (key, value) in values {
            defaults.set(value, forKey: key)
        }
        return defaults
    }

    /// Одинаковый JSON с точностью до порядка ключей и пробелов.
    static func assertSameJSON(_ expected: Data, _ actual: Data, file: StaticString = #filePath, line: UInt = #line) throws {
        let lhs = try XCTUnwrap(JSONSerialization.jsonObject(with: expected) as? NSDictionary, file: file, line: line)
        let rhs = try XCTUnwrap(JSONSerialization.jsonObject(with: actual) as? NSDictionary, file: file, line: line)
        XCTAssertEqual(lhs, rhs, file: file, line: line)
    }

    private static func uuid(_ text: String) -> UUID {
        UUID(uuidString: text) ?? UUID()
    }

    private final class BundleToken {}
}
