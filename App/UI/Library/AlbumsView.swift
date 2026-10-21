import SwiftUI

struct AlbumsView: View {
    @Environment(LibraryStore.self) private var library
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Group {
                if library.isLoaded && library.albums.isEmpty {
                    EmptyLibraryView()
                } else if filtered.isEmpty && !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: DS.Size.albumCard), spacing: DS.Spacing.l)],
                            spacing: DS.Spacing.xl
                        ) {
                            ForEach(filtered) { album in
                                NavigationLink(value: AlbumRoute(id: album.id)) {
                                    AlbumCell(album: album)
                                }
                                .buttonStyle(PressScaleButtonStyle())
                            }
                        }
                        .padding(DS.Spacing.l)
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
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            ArtworkView(key: album.artworkKey, seed: album.title, size: .medium, cornerRadius: DS.Radius.l)
                .dsShadow(DS.Shadow.card)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(album.title)
                    .font(DS.Font.miniTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(DS.LineLimit.rowTitle)
                Text(album.artist)
                    .font(DS.Font.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(DS.LineLimit.rowTitle)
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
                            engine.playTapped(album.trackIDs, at: item.offset)
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
            EmptyStateView(symbol: "square.stack", title: "Альбом не найден")
        }
    }
}

private struct AlbumHeader: View {
    let album: Album
    let tracks: [Track]

    @ScaledMetric(relativeTo: .title) private var artworkSide = DS.Size.albumHeaderArtwork

    var body: some View {
        VStack(spacing: DS.Spacing.l) {
            ArtworkView(key: album.artworkKey, seed: album.title, size: .large, cornerRadius: DS.Radius.xl)
                .frame(maxWidth: artworkSide)
                .dsShadow(DS.Shadow.header)
                .padding(.horizontal, DS.Spacing.xxl)
            VStack(spacing: DS.Spacing.xs) {
                Text(album.title)
                    .font(DS.Font.title)
                    .multilineTextAlignment(.center)
                    .lineLimit(DS.LineLimit.headerTitle)
                Text(album.artist)
                    .font(DS.Font.subtitle)
                    .foregroundStyle(.tint)
                    .multilineTextAlignment(.center)
                    .lineLimit(DS.LineLimit.nowPlayingTitle)
                Text(summary)
                    .font(DS.Font.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DS.Spacing.l)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xl)
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        let total = tracks.reduce(0) { $0 + $1.duration }
        return String(localized: "Песен: \(tracks.count) · \(TimeFormatter.string(from: total))")
    }
}
