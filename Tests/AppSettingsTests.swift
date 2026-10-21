import XCTest
@testable import Player

@MainActor
final class AppSettingsTests: XCTestCase {
    private func makeDefaults() throws -> UserDefaults {
        let name = "PlayerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testDefaults() throws {
        let settings = AppSettings(defaults: try makeDefaults())
        XCTAssertEqual(settings.appearance, .dark)
        XCTAssertEqual(settings.skipInterval, 15)
        XCTAssertEqual(settings.lockScreenControls, .tracks)
        XCTAssertEqual(settings.accent, .fuchsia, "По умолчанию — акцент версии 1.0")
    }

    func testValuesPersist() throws {
        let defaults = try makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.appearance = .light
        settings.skipInterval = 30
        settings.lockScreenControls = .skip
        settings.accent = .neon

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.appearance, .light)
        XCTAssertEqual(reloaded.skipInterval, 30)
        XCTAssertEqual(reloaded.lockScreenControls, .skip)
        XCTAssertEqual(reloaded.accent, .neon)
    }

    func testInvalidStoredIntervalFallsBack() throws {
        let defaults = try makeDefaults()
        defaults.set(7, forKey: "settings.skipInterval")
        XCTAssertEqual(AppSettings(defaults: defaults).skipInterval, 15)
    }

    func testAppearanceMapsToColorScheme() {
        XCTAssertEqual(AppearanceMode.dark.colorScheme, .dark)
        XCTAssertEqual(AppearanceMode.light.colorScheme, .light)
        XCTAssertNil(AppearanceMode.system.colorScheme)
    }
}
