import UIKit
import XCTest
@testable import Player

/// Альтернативные иконки объявлены в Info.plist сборки и у каждой есть превью.
@MainActor
final class AppIconTests: XCTestCase {
    func testAlternateIconsAreDeclaredInInfoPlist() throws {
        let icons = try XCTUnwrap(Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])
        let primary = try XCTUnwrap(icons["CFBundlePrimaryIcon"] as? [String: Any])
        XCTAssertEqual(primary["CFBundleIconName"] as? String, "AppIcon")
        let alternates = try XCTUnwrap(icons["CFBundleAlternateIcons"] as? [String: Any])
        let names = AppIconController.options.compactMap(\.iconName)
        XCTAssertGreaterThanOrEqual(names.count, 6)
        for name in names {
            XCTAssertNotNil(alternates[name], "Иконка \(name) не попала в Info.plist")
        }
    }

    func testEveryOptionHasPreviewAndUniqueName() {
        let options = AppIconController.options
        XCTAssertEqual(Set(options.map(\.id)).count, options.count)
        XCTAssertNil(options.first?.iconName, "Первый вариант — основная иконка")
        for option in options {
            XCTAssertNotNil(UIImage(named: option.previewName), "Нет превью \(option.previewName)")
            XCTAssertFalse(option.title.isEmpty)
        }
    }
}
