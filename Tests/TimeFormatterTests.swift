import XCTest
@testable import Player

final class TimeFormatterTests: XCTestCase {
    func testFormatsMinutesAndSeconds() {
        XCTAssertEqual(TimeFormatter.string(from: 0), "0:00")
        XCTAssertEqual(TimeFormatter.string(from: 5), "0:05")
        XCTAssertEqual(TimeFormatter.string(from: 65), "1:05")
        XCTAssertEqual(TimeFormatter.string(from: 599.9), "9:59")
    }

    func testFormatsHours() {
        XCTAssertEqual(TimeFormatter.string(from: 3600), "1:00:00")
        XCTAssertEqual(TimeFormatter.string(from: 3725), "1:02:05")
    }

    func testInvalidValuesBecomeZero() {
        XCTAssertEqual(TimeFormatter.string(from: -3), "0:00")
        XCTAssertEqual(TimeFormatter.string(from: .nan), "0:00")
        XCTAssertEqual(TimeFormatter.string(from: .infinity), "0:00")
    }
}
