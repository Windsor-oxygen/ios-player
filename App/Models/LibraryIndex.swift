import Foundation

/// Всё, что сохраняется в Library.json.
struct LibraryIndex: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var tracks: [Track]
    var playlists: [Playlist]

    init(version: Int = LibraryIndex.currentVersion, tracks: [Track] = [], playlists: [Playlist] = []) {
        self.version = version
        self.tracks = tracks
        self.playlists = playlists
    }
}
