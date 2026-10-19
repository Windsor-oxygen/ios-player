import SwiftUI

/// Выбор плейлиста для добавления песен.
struct AddToPlaylistSheet: View {
    let trackIDs: [UUID]

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var isCreating = false
    @State private var nameDraft = ""

    var body: some View {
        NavigationStack {
            List {
                Button {
                    nameDraft = ""
                    isCreating = true
                } label: {
                    Label("Новый плейлист…", systemImage: "plus.circle.fill")
                }
                ForEach(library.playlists) { playlist in
                    Button {
                        library.addTracks(trackIDs, toPlaylist: playlist.id)
                        dismiss()
                    } label: {
                        HStack {
                            Text(playlist.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(playlist.trackIDs.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle("В плейлист")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .alert("Новый плейлист", isPresented: $isCreating) {
                TextField("Название", text: $nameDraft)
                Button("Создать") {
                    library.createPlaylist(named: nameDraft, trackIDs: trackIDs)
                    dismiss()
                }
                Button("Отмена", role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Множественный выбор песен из библиотеки.
struct TrackPickerSheet: View {
    let onAdd: ([UUID]) -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var selection = Set<UUID>()
    @State private var query = ""
    @State private var visible: [Track] = []

    var body: some View {
        NavigationStack {
            List(visible, selection: $selection) { track in
                TrackRow(track: track)
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Поиск")
            .task(id: query) {
                let available = library.tracks.filter(\.isAvailable)
                visible = await LibraryQuery.songs(available, sort: .title, query: query)
            }
            .navigationTitle("Добавить песни")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить (\(selection.count))") {
                        // Сохраняем порядок, в котором песни видны в списке.
                        onAdd(visible.map(\.id).filter(selection.contains))
                        dismiss()
                    }
                    .disabled(selection.isEmpty)
                }
            }
        }
    }
}
