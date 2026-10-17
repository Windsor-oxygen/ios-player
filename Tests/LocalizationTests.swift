import XCTest
@testable import Player

/// Проверяет, что String Catalog скомпилирован в сборку для обоих языков.
final class LocalizationTests: XCTestCase {
    private func bundle(for language: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"), "Нет \(language).lproj")
        return try XCTUnwrap(Bundle(path: path))
    }

    func testBothLanguagesShipped() {
        XCTAssertTrue(Bundle.main.localizations.contains("ru"))
        XCTAssertTrue(Bundle.main.localizations.contains("en"))
    }

    func testEnglishTranslations() throws {
        let english = try bundle(for: "en")
        XCTAssertEqual(english.localizedString(forKey: "Песни", value: nil, table: nil), "Songs")
        XCTAssertEqual(english.localizedString(forKey: "Песен: %lld", value: nil, table: nil), "Songs: %lld")
        XCTAssertEqual(english.localizedString(forKey: "CFBundleDisplayName", value: nil, table: "InfoPlist"), "Player")
    }

    func testRussianIsSource() throws {
        let russian = try bundle(for: "ru")
        XCTAssertEqual(russian.localizedString(forKey: "Песни", value: nil, table: nil), "Песни")
        XCTAssertEqual(russian.localizedString(forKey: "CFBundleDisplayName", value: nil, table: "InfoPlist"), "Плеер")
    }
}
