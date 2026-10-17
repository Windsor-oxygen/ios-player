import SwiftUI

struct AlbumsView: View {
    @Environment(LibraryStore.self) private var library
    @State private var query = ""

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        NavigationStack {
            Group {
                if library.isLoaded && library.albums.isEmpty {
                    EmptyLibraryView()
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 24) {
                            ForEach(filtered) { album in
                                NavigationLink(value: AlbumRoute(id: album.id)) {
                                    AlbumCell(album: album)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Альбомы")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { AddMusicMenu() }
            }
            .searchable(text: $query, prompt: "Альбом или исполнитель")
            .navigationDestination(for: AlbumRoute.self) { AlbumDetailView(albumID: $0.id) }
        }
    }

    /// Альбомов на порядок меньше, чем песен, — фильтр дешёвый.
    private var filtered: [Album] {
        guard !query.isEmpty else { return library.albums }
        return library.albums.filter {
            $0.title.localizedStandardContains(query) || $0.artist.localizedStandardContains(query)
        }
    }
}

struct AlbumCell: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkView(key: album.artworkKey, size: .medium, cornerRadius: 12)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(album.artist)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(album.title), \(album.artist)")
        .accessibilityAddTraits(.isButton)
    }
}

struct AlbumDetailView: View {
    let albumID: String

    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackEngine.self) private var engine
    @State private var pendingDeletion: Track?
    @State private var playlistTarget: TrackSelection?

    var body: some View {
        if let album = library.album(id: albumID) {
            let tracks = library.tracks(ids: album.trackIDs)
            List {
                Section {
                    AlbumHeader(album: album, tracks: tracks)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                Section {
                    PlayShuffleButtons(trackIDs: album.trackIDs)
                        .listRowSeparator(.hidden)
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { item in
                        Button {
                            engine.play(album.trackIDs, startAt: item.offset)
                        } label: {
                            TrackRow(track: item.element, showsTrackNumber: true)
                        }
                        .trackActions(item.element, pendingDeletion: $pendingDeletion, playlistTarget: $playlistTarget)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(album.title)
            .navigationBarTitleDisplayMode(.inline)
            .trackActionsHost(pendingDeletion: $pendingDeletion, playlistTarget: $playlistTarget)
        } else {
            ContentUnavailableView("Альбом не найден", systemImage: "square.stack")
        }
    }
}

private struct AlbumHeader: View {
    let album: Album
    let tracks: [Track]

    var body: some View {
        VStack(spacing: 16) {
            ArtworkView(key: album.artworkKey, size: .large, cornerRadius: 16)
                .frame(width: 240, height: 240)
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
            VStack(spacing: 4) {
                Text(album.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Text(album.artist)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .lineLimit(2)
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        let total = tracks.reduce(0) { $0 + $1.duration }
        return String(localized: "Песен: \(tracks.count) · \(TimeFormatter.string(from: total))")
    }
}
