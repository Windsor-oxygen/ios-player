import Foundation

/// Спасает из повреждённого Library.json всё, что читается: каждый трек и
/// плейлист декодируется отдельно. Трек с испорченными полями сохраняет хотя бы
/// `id` и путь — ссылки плейлистов на него не рвутся, а теги перечитаются.
enum LossyLibraryDecoder {
    static func decode(_ data: Data) -> LibraryIndex {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return LibraryIndex()
        }
        let decoder = JSONDecoder()
        let tracks = elements(root["tracks"]).compactMap { element in
            decodeElement(Track.self, element, decoder) ?? salvageTrack(element)
        }
        let playlists = elements(root["playlists"]).compactMap { element in
            decodeElement(Playlist.self, element, decoder) ?? salvagePlaylist(element)
        }
        return LibraryIndex(tracks: tracks, playlists: playlists)
    }

    private static func elements(_ value: Any?) -> [[String: Any]] {
        (value as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }

    private static func decodeElement<T: Decodable>(_ type: T.Type, _ element: [String: Any], _ decoder: JSONDecoder) -> T? {
        guard let data = try? JSONSerialization.data(withJSONObject: element) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private static func uuid(_ value: Any?) -> UUID? {
        (value as? String).flatMap(UUID.init(uuidString:))
    }

    private static func salvageTrack(_ element: [String: Any]) -> Track? {
        guard let id = uuid(element["id"]),
              let path = element["relativePath"] as? String, !path.isEmpty else { return nil }
        return Track(
            id: id,
            relativePath: path,
            title: (element["title"] as? String) ?? Track.defaultTitle(forRelativePath: path),
            artist: nil,
            album: nil,
            trackNumber: nil,
            discNumber: nil,
            duration: 0,
            // Нулевой размер не совпадёт с файлом на диске — сверка перечитает теги.
            fileSize: 0,
            modificationDate: .distantPast,
            dateAdded: .now,
            artworkKey: nil,
            isMissing: false,
            isUnplayable: false,
            needsMetadata: true
        )
    }

    private static func salvagePlaylist(_ element: [String: Any]) -> Playlist? {
        guard let id = uuid(element["id"]) else { return nil }
        let name = (element["name"] as? String) ?? String(localized: "Восстановленный плейлист")
        let trackIDs = (element["trackIDs"] as? [Any])?.compactMap { uuid($0) } ?? []
        return Playlist(id: id, name: name, trackIDs: trackIDs)
    }
}
