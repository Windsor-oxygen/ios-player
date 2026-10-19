import Foundation
@testable import Player

enum TestSupport {
    /// Изолированные папки Documents / Application Support / Caches во временной директории.
    static func makeLocations() throws -> StorageLocations {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "PlayerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let locations = StorageLocations(
            documents: root.appending(path: "Documents", directoryHint: .isDirectory),
            applicationSupport: root.appending(path: "Support", directoryHint: .isDirectory),
            caches: root.appending(path: "Caches", directoryHint: .isDirectory)
        )
        for url in [locations.documents, locations.applicationSupport, locations.caches] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return locations
    }

    static func cleanUp(_ locations: StorageLocations) {
        try? FileManager.default.removeItem(at: locations.documents.deletingLastPathComponent())
    }

    /// Корректный WAV (16 бит, моно, тишина) — его AVFoundation умеет воспроизводить.
    static func wavData(seconds: Double = 0.5, sampleRate: Int = 8000) -> Data {
        let dataSize = Int(Double(sampleRate) * seconds) * 2
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize))
        data.append(Data(count: dataSize))
        return data
    }

    @discardableResult
    static func write(_ data: Data, to url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    static func track(
        _ title: String,
        path: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        dateAdded: Date = Date(timeIntervalSinceReferenceDate: 0),
        size: Int64 = 100,
        modified: Date = Date(timeIntervalSinceReferenceDate: 1000)
    ) -> Track {
        Track(
            id: UUID(),
            relativePath: path ?? "Music/\(title).mp3",
            title: title,
            artist: artist,
            album: album,
            trackNumber: trackNumber,
            discNumber: discNumber,
            duration: 180,
            fileSize: size,
            modificationDate: modified,
            dateAdded: dateAdded,
            artworkKey: nil,
            isMissing: false,
            isUnplayable: false,
            needsMetadata: false
        )
    }
}
