import SwiftUI

struct ArtistsView: View {
    @Environment(LibraryStore.self) private var library
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Group {
                if library.isLoaded && library.artists.isEmpty {
                    EmptyLibraryView()
                } else if filtered.isEmpty && !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(filtered) { artist in
                        NavigationLink(value: ArtistRoute(id: artist.id)) {
                            ArtistRow(artist: artist)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Исполнители")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { AddMusicMenu() }
            }
            .searchable(text: $query, prompt: "Исполнитель")
            .navigationDestination(for: ArtistRoute.self) { ArtistDetailView(artistID: $0.id) }
            .navigationDestination(for: AlbumRoute.self) { AlbumDetailView(albumID: $0.id) }
        }
    }

    private var filtered: [Artist] {
        guard !query.isEmpty else { return library.artists }
        return library.artists.filter { $0.name.localizedStandardContains(query) }
    }
}

private struct ArtistRow: View {
    let artist: Artist

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(key: artist.artworkKey, cornerRadius: 24)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                    .lineLimit(1)
                Text("Песен: \(artist.trackIDs.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct ArtistDetailView: View {
    let artistID: String

    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackEngine.self) private var engine
    @State private var pendingDeletion: Track?
    @State private var playlistTarget: TrackSelection?

    var body: some View {
        if let artist = library.artist(id: artistID) {
            let albums = artist.albumIDs.compactMap { library.album(id: $0) }
            List {
                if !albums.isEmpty {
                    Section("Альбомы") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 16) {
                                ForEach(albums) { album in
                                    NavigationLink(value: AlbumRoute(id: album.id)) {
                                        AlbumCell(album: album)
                                            .frame(width: 144)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .listRowInsets(EdgeInsets())
                    }
                }
                Section("Песни") {
                    PlayShuffleButtons(trackIDs: artist.trackIDs)
                        .listRowSeparator(.hidden)
                    ForEach(Array(library.tracks(ids: artist.trackIDs).enumerated()), id: \.element.id) { item in
                        Button {
                            engine.play(artist.trackIDs, startAt: item.offset)
                        } label: {
                            TrackRow(track: item.element)
                        }
                        .trackActions(item.element, pendingDeletion: $pendingDeletion, playlistTarget: $playlistTarget)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(artist.name)
            .trackActionsHost(pendingDeletion: $pendingDeletion, playlistTarget: $playlistTarget)
        } else {
            ContentUnavailableView("Исполнитель не найден", systemImage: "music.mic")
        }
    }
}
