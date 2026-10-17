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

    func testDisplayName() {
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "Плеер")
    }
}
