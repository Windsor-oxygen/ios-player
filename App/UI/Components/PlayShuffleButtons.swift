import SwiftUI

/// «Слушать» и «Перемешать» для альбома, исполнителя или плейлиста.
struct PlayShuffleButtons: View {
    let trackIDs: [UUID]
    @Environment(PlaybackEngine.self) private var engine

    var body: some View {
        HStack(spacing: 16) {
            Button {
                engine.play(trackIDs)
            } label: {
                Label("Слушать", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            Button {
                engine.play(trackIDs, shuffled: true)
            } label: {
                Label("Перемешать", systemImage: "shuffle")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .font(.body.weight(.semibold))
        .disabled(trackIDs.isEmpty)
    }
}
