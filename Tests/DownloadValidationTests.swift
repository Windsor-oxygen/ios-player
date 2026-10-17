import XCTest
@testable import Player

final class DownloadURLValidatorTests: XCTestCase {
    private func error(_ text: String) -> DownloadURLError? {
        if case .failure(let error) = DownloadURLValidator.validate(text) { return error }
        return nil
    }

    func testAcceptsHTTPS() throws {
        let url = try DownloadURLValidator.validate("  https://example.com/music/song.mp3 \n").get()
        XCTAssertEqual(url.host(), "example.com")
        XCTAssertEqual(url.pathExtension, "mp3")
        XCTAssertNoThrow(try DownloadURLValidator.validate("HTTPS://EXAMPLE.COM/a.flac").get())
    }

    func testAcceptsUnknownExtensionForContentTypeCheckLater() {
        XCTAssertNoThrow(try DownloadURLValidator.validate("https://example.com/download.php?id=1").get())
        XCTAssertNoThrow(try DownloadURLValidator.validate("https://example.com/stream").get())
    }

    func testRejectsHTTPWithHint() {
        XCTAssertEqual(error("http://example.com/song.mp3"), .insecureHTTP)
        XCTAssertTrue(DownloadURLError.insecureHTTP.errorDescription?.contains("https://") ?? false)
    }

    func testRejectsEmptyAndMalformed() {
        XCTAssertEqual(error(""), .empty)
        XCTAssertEqual(error("   "), .empty)
        XCTAssertEqual(error("example.com/song.mp3"), .malformed)
        XCTAssertEqual(error("https://"), .malformed)
    }

    func testRejectsOtherSchemes() {
        XCTAssertEqual(error("ftp://example.com/a.mp3"), .unsupportedScheme("ftp"))
        XCTAssertEqual(error("file:///etc/passwd"), .unsupportedScheme("file"))
    }

    func testRejectsUnsupportedAudioExtension() {
        XCTAssertEqual(error("https://example.com/song.ogg"), .unsupportedFormat("ogg"))
        XCTAssertEqual(error("https://example.com/song.OPUS"), .unsupportedFormat("opus"))
    }
}

final class DownloadNamingTests: XCTestCase {
    private let base = URL(string: "https://example.com/files/download")

    private func name(_ url: URL?, suggested: String?, mime: String?) -> Result<String, DownloadError>? {
        guard let url else { return nil }
        return DownloadNaming.fileName(requestURL: url, suggestedFilename: suggested, mimeType: mime)
    }

    func testUsesSuggestedFilenameWithSupportedExtension() {
        XCTAssertEqual(name(base, suggested: "Song.mp3", mime: "audio/mpeg"), .success("Song.mp3"))
        XCTAssertEqual(name(base, suggested: "Track.flac", mime: "application/octet-stream"), .success("Track.flac"))
    }

    func testAddsExtensionFromMIME() {
        XCTAssertEqual(name(base, suggested: "download", mime: "audio/mpeg"), .success("download.mp3"))
        XCTAssertEqual(name(base, suggested: nil, mime: "audio/x-m4a; charset=binary"), .success("download.m4a"))
    }

    func testRejectsWebPage() {
        XCTAssertEqual(name(base, suggested: "song.mp3", mime: "text/html; charset=utf-8"), .failure(.webPage))
    }

    func testRejectsUnsupportedAudio() {
        XCTAssertEqual(name(base, suggested: "song.ogg", mime: "audio/ogg"), .failure(.unsupportedFormat(".ogg")))
        XCTAssertEqual(name(base, suggested: "download", mime: "audio/ogg"), .failure(.unsupportedFormat("audio/ogg")))
    }

    func testRejectsNonAudio() {
        XCTAssertEqual(name(base, suggested: "data.json", mime: "application/json"), .failure(.notAudio("application/json")))
    }
}

final class AudioFormatTests: XCTestCase {
    func testClassification() {
        for ext in ["mp3", "M4A", "aac", "wav", "aiff", "aif", "flac", "caf", "alac"] {
            XCTAssertEqual(AudioFormat.classify(fileExtension: ext), .supported, ext)
        }
        XCTAssertEqual(AudioFormat.classify(fileExtension: "ogg"), .unsupported("ogg"))
        XCTAssertEqual(AudioFormat.classify(fileExtension: "WMA"), .unsupported("wma"))
        XCTAssertEqual(AudioFormat.classify(fileExtension: "pdf"), .notAudio)
        XCTAssertEqual(AudioFormat.classify(fileExtension: ""), .notAudio)
    }

    func testMIMEMapping() {
        XCTAssertEqual(AudioFormat.fileExtension(forMIMEType: "audio/mpeg"), "mp3")
        XCTAssertEqual(AudioFormat.fileExtension(forMIMEType: "AUDIO/FLAC"), "flac")
        XCTAssertNil(AudioFormat.fileExtension(forMIMEType: "application/octet-stream"))
        XCTAssertTrue(AudioFormat.isUnsupportedAudioMIME("audio/opus"))
        XCTAssertTrue(AudioFormat.isUnsupportedAudioMIME("application/ogg"))
        XCTAssertFalse(AudioFormat.isUnsupportedAudioMIME("audio/mp4"))
    }
}
