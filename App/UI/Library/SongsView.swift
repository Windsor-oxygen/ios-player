import SwiftUI

struct SongsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackEngine.self) private var engine
    @Environment(AppPresenter.self) private var presenter
    @AppStorage("songs.sort") private var sort: SongSort = .title
    @State private var query = ""
    @State private var visible: [Track] = []
    @State private var pendingDeletion: Track?
    @State private var playlistTarget: TrackSelection?

    /// Список пересчитывается при изменении библиотеки, сортировки или запроса.
    private var listKey: String {
        "\(library.revision)|\(sort.rawValue)|\(query)"
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Песни")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            presenter.showsSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .accessibilityLabel("Настройки")
                        }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        sortMenu
                        AddMusicMenu()
                    }
                }
                .searchable(text: $query, prompt: "Название, исполнитель, альбом")
                .refreshable { await library.refresh() }
                .task(id: listKey) {
                    // Небольшая задержка при вводе — не пересчитываем на каждую букву.
                    if !query.isEmpty {
                        try? await Task.sleep(for: .milliseconds(200))
                        if Task.isCancelled { return }
                    }
                    let result = await LibraryQuery.songs(library.tracks, sort: sort, query: query)
                    if !Task.isCancelled { visible = result }
                }
                .trackActionsHost(pendingDeletion: $pendingDeletion, playlistTarget: $playlistTarget)
        }
    }

    @ViewBuilder
    private var content: some View {
        if library.isLoaded && library.tracks.isEmpty {
            EmptyLibraryView()
        } else if !query.isEmpty && visible.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List {
                ForEach(Array(visible.enumerated()), id: \.element.id) { item in
                    Button {
                        engine.play(visible.map(\.id), startAt: item.offset)
                    } label: {
                        TrackRow(track: item.element)
                    }
                    .trackActions(item.element, pendingDeletion: $pendingDeletion, playlistTarget: $playlistTarget)
                }
            }
            .listStyle(.plain)
            .overlay(alignment: .bottom) {
                if library.isRefreshing {
                    ProgressView()
                        .padding(8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 16)
                }
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Сортировка", selection: $sort) {
                ForEach(SongSort.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .accessibilityLabel("Сортировка")
        }
    }
}
