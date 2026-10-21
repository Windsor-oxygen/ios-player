import Foundation

struct Album: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
    let trackIDs: [UUID]
    let artworkKey: String?
}

struct Artist: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let albumIDs: [String]
    let trackIDs: [UUID]
    let artworkKey: String?
}

enum SongSort: String, CaseIterable, Identifiable, Sendable {
    case title
    case artist
    case album
    case dateAdded

    var id: String { rawValue }

    var label: String {
        switch self {
        case .title: String(localized: "По названию")
        case .artist: String(localized: "По исполнителю")
        case .album: String(localized: "По альбому")
        case .dateAdded: String(localized: "Сначала новые")
        }
    }
}

/// Сортировка, поиск и группировка. Чистые функции — покрыты тестами.
enum LibraryQuery {
    static var unknownArtist: String { String(localized: "Неизвестный исполнитель") }
    static var unknownAlbum: String { String(localized: "Неизвестный альбом") }
    /// Сколько первых песен плейлиста просматривать в поисках обложки.
    static let playlistCoverLookahead = 20
    /// Пауза после ввода в поиске, прежде чем пересчитывать список.
    static let searchDebounce = Duration.milliseconds(200)

    /// Отсортированные и отфильтрованные песни. `nonisolated async` — выполняется вне main thread.
    static func songs(_ tracks: [Track], sort: SongSort, query: String) async -> [Track] {
        sortedSongs(filter(tracks, query: query), by: sort)
    }

    static func filter(_ tracks: [Track], query: String) -> [Track] {
        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return tracks }
        return tracks.filter { track in
            tokens.allSatisfy { token in
                track.title.localizedStandardContains(token)
                    || (track.artist?.localizedStandardContains(token) ?? false)
                    || (track.album?.localizedStandardContains(token) ?? false)
            }
        }
    }

    static func sortedSongs(_ tracks: [Track], by sort: SongSort) -> [Track] {
        switch sort {
        case .title:
            tracks.sorted { ordered($0.title, $1.title, tie: ($0.id.uuidString, $1.id.uuidString)) }
        case .artist:
            tracks.sorted {
                let a = $0.artist ?? unknownArtist, b = $1.artist ?? unknownArtist
                return a == b ? ordered($0.title, $1.title, tie: ($0.id.uuidString, $1.id.uuidString)) : ordered(a, b, tie: ($0.id.uuidString, $1.id.uuidString))
            }
        case .album:
            tracks.sorted {
                let a = $0.album ?? unknownAlbum, b = $1.album ?? unknownAlbum
                return a == b ? albumOrder($0, $1) : ordered(a, b, tie: ($0.id.uuidString, $1.id.uuidString))
            }
        case .dateAdded:
            tracks.sorted {
                $0.dateAdded == $1.dateAdded
                    ? ordered($0.title, $1.title, tie: ($0.id.uuidString, $1.id.uuidString))
                    : $0.dateAdded > $1.dateAdded
            }
        }
    }

    /// Порядок внутри альбома: диск → номер трека → название.
    static func albumOrder(_ lhs: Track, _ rhs: Track) -> Bool {
        let discL = lhs.discNumber ?? 1, discR = rhs.discNumber ?? 1
        if discL != discR { return discL < discR }
        switch (lhs.trackNumber, rhs.trackNumber) {
        case let (l?, r?) where l != r: return l < r
        case (_?, nil): return true
        case (nil, _?): return false
        default: return ordered(lhs.title, rhs.title, tie: (lhs.id.uuidString, rhs.id.uuidString))
        }
    }

    static func albums(from tracks: [Track]) -> [Album] {
        var groups: [String: [Track]] = [:]
        for track in tracks {
            groups[albumKey(for: track), default: []].append(track)
        }
        return groups.map { key, members in
            let sorted = members.sorted(by: albumOrder)
            let first = sorted.first
            return Album(
                id: key,
                title: first?.album ?? unknownAlbum,
                artist: first?.artist ?? unknownArtist,
                trackIDs: sorted.map(\.id),
                artworkKey: sorted.lazy.compactMap(\.artworkKey).first
            )
        }
        .sorted { ordered($0.title, $1.title, tie: ($0.id, $1.id)) }
    }

    static func artists(from tracks: [Track]) -> [Artist] {
        var groups: [String: [Track]] = [:]
        for track in tracks {
            groups[normalize(track.artist ?? ""), default: []].append(track)
        }
        return groups.map { key, members in
            let byTitle = members.sorted { ordered($0.title, $1.title, tie: ($0.id.uuidString, $1.id.uuidString)) }
            let byAlbum = members.sorted {
                let a = $0.album ?? unknownAlbum, b = $1.album ?? unknownAlbum
                return a == b ? albumOrder($0, $1) : ordered(a, b, tie: ($0.id.uuidString, $1.id.uuidString))
            }
            var seenAlbums = Set<String>()
            let albumIDs = byAlbum.map(albumKey).filter { seenAlbums.insert($0).inserted }
            return Artist(
                id: key.isEmpty ? "\u{0}unknown" : key,
                name: members.first?.artist ?? unknownArtist,
                albumIDs: albumIDs,
                trackIDs: byTitle.map(\.id),
                artworkKey: byAlbum.lazy.compactMap(\.artworkKey).first
            )
        }
        .sorted { ordered($0.name, $1.name, tie: ($0.id, $1.id)) }
    }

    static func albumKey(for track: Track) -> String {
        "\(normalize(track.artist ?? ""))\u{1F}\(normalize(track.album ?? ""))"
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func ordered(_ lhs: String, _ rhs: String, tie: (String, String)) -> Bool {
        let result = lhs.localizedStandardCompare(rhs)
        return result == .orderedSame ? tie.0 < tie.1 : result == .orderedAscending
    }
}
