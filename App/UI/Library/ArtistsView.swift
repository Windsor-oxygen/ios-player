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
        HStack(spacing: DS.Spacing.m) {
            ArtworkView(key: artist.artworkKey, seed: artist.name, cornerRadius: DS.Size.rowArtwork * DS.Radius.circleRatio)
                .frame(width: DS.Size.rowArtwork, height: DS.Size.rowArtwork)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(artist.name)
                    .font(DS.Font.body)
                    .lineLimit(DS.LineLimit.rowTitle)
                Text("Песен: \(artist.trackIDs.count)")
                    .font(DS.Font.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, DS.Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}

struct ArtistDetailView: View {
    let artistID: String

    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackEngine.self) private var engine
    @State private var pendingDeletion: Track?
    @State private var playlistTarget: TrackSelection?
    @ScaledMetric(relativeTo: .body) private var carouselWidth = DS.Size.albumCarousel

    var body: some View {
        if let artist = library.artist(id: artistID) {
            let albums = artist.albumIDs.compactMap { library.album(id: $0) }
            List {
                if !albums.isEmpty {
                    Section("Альбомы") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: DS.Spacing.l) {
                                ForEach(albums) { album in
                                    NavigationLink(value: AlbumRoute(id: album.id)) {
                                        AlbumCell(album: album)
                                            .frame(width: carouselWidth)
                                    }
                                    .buttonStyle(PressScaleButtonStyle())
                                }
                            }
                            .padding(.horizontal, DS.Spacing.l)
                            .padding(.vertical, DS.Spacing.s)
                        }
                        .listRowInsets(EdgeInsets())
                    }
                }
                Section("Песни") {
                    PlayShuffleButtons(trackIDs: artist.trackIDs)
                        .listRowSeparator(.hidden)
                    ForEach(Array(library.tracks(ids: artist.trackIDs).enumerated()), id: \.element.id) { item in
                        Button {
                            engine.playTapped(artist.trackIDs, at: item.offset)
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
            EmptyStateView(symbol: "music.mic", title: "Исполнитель не найден")
        }
    }
}
