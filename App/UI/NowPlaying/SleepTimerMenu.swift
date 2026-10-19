import SwiftUI

struct SleepTimerMenu: View {
    @Environment(PlaybackEngine.self) private var engine

    var body: some View {
        Menu {
            switch engine.sleepTimer {
            case .off:
                EmptyView()
            case .at(let date):
                Section("Остановится в \(date.formatted(date: .omitted, time: .shortened))") {
                    cancelButton
                }
            case .endOfTrack:
                Section("Остановится в конце трека") {
                    cancelButton
                }
            }
            Section("Таймер сна") {
                ForEach(PlaybackEngine.sleepTimerOptions, id: \.self) { minutes in
                    Button("\(minutes) мин") { engine.startSleepTimer(minutes: minutes) }
                }
                Button("В конце трека") { engine.startSleepTimerAtEndOfTrack() }
            }
        } label: {
            Image(systemName: engine.sleepTimer == .off ? "moon.zzz" : "moon.zzz.fill")
                .font(DS.Font.controlIcon)
                .frame(width: DS.Size.tapTarget, height: DS.Size.tapTarget)
                .foregroundStyle(engine.sleepTimer == .off ? DS.Palette.onArtworkSecondary : Color.accentColor)
        }
        .accessibilityLabel(engine.sleepTimer == .off ? "Таймер сна" : "Таймер сна включён")
    }

    private var cancelButton: some View {
        Button("Выключить таймер", role: .destructive) { engine.cancelSleepTimer() }
    }
}
