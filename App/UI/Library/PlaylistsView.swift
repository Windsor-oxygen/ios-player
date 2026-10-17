import SwiftUI

struct PlaylistsView: View {
    @Environment(LibraryStore.self) private var library
    @State private var isCreating = false
    @State private var renaming: Playlist?
    @State private var pendingDeletion: Playlist?
    @State private var nameDraft = ""

    var body: some View {
        NavigationStack {
            List {
                Button {
                    nameDraft = ""
                    isCreating = true
                } label: {
                    Label("Новый плейлист", systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                }
                ForEach(library.playlists) { playlist in
                    NavigationLink(value: PlaylistRoute(id: playlist.id)) {
                        PlaylistRow(playlist: playlist)
                    }
                    .contextMenu {
                        Button {
                            nameDraft = playlist.name
                            renaming = playlist
                        } label: {
                            Label("Переименовать", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            pendingDeletion = playlist
                        } label: {
                            Label("Удалить плейлист", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            pendingDeletion = playlist
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if library.playlists.isEmpty {
                    ContentUnavailableView(
                        "Нет плейлистов",
                        systemImage: "music.note.list",
                        description: Text("Создайте плейлист и добавьте в него песни через долгое нажатие на песню.")
                    )
                    .allowsHitTesting(false)
                }
            }
            .navigationTitle("Плейлисты")
            .navigationDestination(for: PlaylistRoute.self) { PlaylistDetailView(playlistID: $0.id) }
            .alert("Новый плейлист", isPresented: $isCreating) {
                TextField("Название", text: $nameDraft)
                Button("Создать") { library.createPlaylist(named: nameDraft) }
                Button("Отмена", role: .cancel) {}
            }
            .alert("Переименовать плейлист", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            ), presenting: renaming) { playlist in
                TextField("Название", text: $nameDraft)
                Button("Сохранить") { library.renamePlaylist(playlist.id, to: nameDraft) }
                Button("Отмена", role: .cancel) {}
            }
            .confirmationDialog(
                "Удалить плейлист «\(pendingDeletion?.name ?? "")»?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { playlist in
                Button("Удалить плейлист", role: .destructive) { library.deletePlaylist(playlist.id) }
                Button("Отмена", role: .cancel) {}
            } message: { _ in
                Text("Сами песни останутся в библиотеке.")
            }
        }
    }
}

private struct PlaylistRow: View {
    let playlist: Playlist
    @Environment(LibraryStore.self) private var library

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(key: coverKey, cornerRadius: 8)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .lineLimit(1)
                Text("Песен: \(playlist.trackIDs.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// Обложка первой песни с обложкой (ограничиваемся первыми 20, чтобы не перебирать всё).
    private var coverKey: String? {
        playlist.trackIDs.prefix(20).lazy.compactMap { library.tracksByID[$0]?.artworkKey }.first
    }
}

struct PlaylistDetailView: View {
    let playlistID: UUID

    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackEngine.self) private var engine
    @State private var isPicking = false
    @State private var isRenaming = false
    @State private var nameDraft = ""

    var body: some View {
        if let playlist = library.playlist(id: playlistID) {
            List {
                if !playlist.trackIDs.isEmpty {
                    PlayShuffleButtons(trackIDs: playlist.trackIDs)
                        .listRowSeparator(.hidden)
                        .moveDisabled(true)
                        .deleteDisabled(true)
                }
                ForEach(Array(playlist.trackIDs.enumerated()), id: \.offset) { item in
                    if let track = library.tracksByID[item.element] {
                        Button {
                            engine.play(playlist.trackIDs, startAt: item.offset)
                        } label: {
                            TrackRow(track: track)
                        }
                    } else {
                        Text("Песня удалена")
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { library.removeTracks(at: $0, fromPlaylist: playlistID) }
                .onMove { library.moveTracks(from: $0, to: $1, inPlaylist: playlistID) }
            }
            .listStyle(.plain)
            .overlay {
                if playlist.trackIDs.isEmpty {
                    ContentUnavailableView {
                        Label("Плейлист пуст", systemImage: "music.note.list")
                    } actions: {
                        Button("Добавить песни") { isPicking = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle(playlist.name)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isPicking = true
                        } label: {
                            Label("Добавить песни", systemImage: "plus")
                        }
                        Button {
                            nameDraft = playlist.name
                            isRenaming = true
                        } label: {
                            Label("Переименовать", systemImage: "pencil")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel("Действия с плейлистом")
                    }
                    EditButton()
                }
            }
            .sheet(isPresented: $isPicking) {
                TrackPickerSheet { ids in library.addTracks(ids, toPlaylist: playlistID) }
            }
            .alert("Переименовать плейлист", isPresented: $isRenaming) {
                TextField("Название", text: $nameDraft)
                Button("Сохранить") { library.renamePlaylist(playlistID, to: nameDraft) }
                Button("Отмена", role: .cancel) {}
            }
        } else {
            ContentUnavailableView("Плейлист не найден", systemImage: "music.note.list")
        }
    }
}
