import SwiftUI

/// Набор треков, над которым выполняется действие из меню.
struct TrackSelection: Identifiable {
    let id = UUID()
    let trackIDs: [UUID]
}

extension View {
    /// Контекстное меню и свайп «Удалить» для строки трека.
    func trackActions(_ track: Track, pendingDeletion: Binding<Track?>, playlistTarget: Binding<TrackSelection?>) -> some View {
        contextMenu {
            Button {
                playlistTarget.wrappedValue = TrackSelection(trackIDs: [track.id])
            } label: {
                Label("Добавить в плейлист…", systemImage: "text.badge.plus")
            }
            Divider()
            Button(role: .destructive) {
                pendingDeletion.wrappedValue = track
            } label: {
                Label("Удалить с iPhone", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Без role: .destructive — иначе строка исчезает до подтверждения.
            Button {
                pendingDeletion.wrappedValue = track
            } label: {
                Label("Удалить", systemImage: "trash")
            }
            .tint(.red)
        }
    }

    /// Подтверждение удаления и выбор плейлиста — вешается на список один раз.
    func trackActionsHost(pendingDeletion: Binding<Track?>, playlistTarget: Binding<TrackSelection?>) -> some View {
        modifier(TrackActionsHost(pendingDeletion: pendingDeletion, playlistTarget: playlistTarget))
    }
}

private struct TrackActionsHost: ViewModifier {
    @Binding var pendingDeletion: Track?
    @Binding var playlistTarget: TrackSelection?
    @Environment(LibraryStore.self) private var library

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Удалить «\(pendingDeletion?.title ?? "")»?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { track in
                Button("Удалить с iPhone", role: .destructive) {
                    Task { await library.delete([track.id]) }
                }
                Button("Отмена", role: .cancel) {}
            } message: { _ in
                Text("Файл будет удалён из папки приложения и из всех плейлистов.")
            }
            .sheet(item: $playlistTarget) { selection in
                AddToPlaylistSheet(trackIDs: selection.trackIDs)
            }
    }
}
