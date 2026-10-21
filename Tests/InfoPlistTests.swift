import XCTest

/// Проверяет ключи Info.plist, от которых зависит фоновое воспроизведение
/// и видимость папки приложения в «Файлах».
final class InfoPlistTests: XCTestCase {
    private var info: [String: Any] {
        Bundle.main.infoDictionary ?? [:]
    }

    func testBackgroundAudioModeEnabled() throws {
        let modes = try XCTUnwrap(info["UIBackgroundModes"] as? [String])
        XCTAssertTrue(modes.contains("audio"))
    }

    func testFileSharingEnabled() {
        XCTAssertEqual(info["UIFileSharingEnabled"] as? Bool, true)
        XCTAssertEqual(info["LSSupportsOpeningDocumentsInPlace"] as? Bool, true)
    }

    func testAudioDocumentTypesDeclared() throws {
        let types = try XCTUnwrap(info["CFBundleDocumentTypes"] as? [[String: Any]])
        let utis = types.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
        for uti in ["public.audio", "public.mp3", "com.apple.m4a-audio", "public.mpeg-4-audio",
                    "com.microsoft.waveform-audio", "public.aiff-audio", "org.xiph.flac"] {
            XCTAssertTrue(utis.contains(uti), "Нет UTI \(uti)")
        }
    }

    func testDisplayNameIsPlayerEverywhere() {
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "Player")
        XCTAssertEqual(info["CFBundleName"] as? String, "Player")
        // Имя не переопределяется локализациями: под иконкой «Player» на любом языке.
        for language in ["ru", "en"] {
            let path = Bundle.main.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil, forLocalization: language)
            XCTAssertNil(path, "Лишний InfoPlist.strings для \(language)")
        }
    }

    func testVersion() {
        XCTAssertEqual(info["CFBundleShortVersionString"] as? String, "1.1")
        let build = Int(info["CFBundleVersion"] as? String ?? "") ?? 0
        XCTAssertGreaterThan(build, 1, "Номер сборки должен расти: в 1.0 был 1")
    }
}
