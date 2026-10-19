import SwiftUI

/// «Слушать» и «Перемешать» для альбома, исполнителя или плейлиста.
struct PlayShuffleButtons: View {
    let trackIDs: [UUID]
    @Environment(PlaybackEngine.self) private var engine
    @State private var taps = 0

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Spacing.m) { buttons }
            VStack(spacing: DS.Spacing.s) { buttons }
        }
        .controlSize(.large)
        .font(DS.Font.bodyEmphasized)
        .disabled(trackIDs.isEmpty)
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
    }

    @ViewBuilder
    private var buttons: some View {
        Button {
            taps += 1
            engine.play(trackIDs)
        } label: {
            Label("Слушать", systemImage: "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        Button {
            taps += 1
            engine.play(trackIDs, shuffled: true)
        } label: {
            Label("Перемешать", systemImage: "shuffle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}
