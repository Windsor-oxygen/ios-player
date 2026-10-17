import SwiftUI

struct SleepTimerMenu: View {
    @Environment(PlaybackEngine.self) private var engine

    private static let options = [5, 15, 30, 45, 60, 90]

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
                ForEach(Self.options, id: \.self) { minutes in
                    Button("\(minutes) мин") { engine.startSleepTimer(minutes: minutes) }
                }
                Button("В конце трека") { engine.startSleepTimerAtEndOfTrack() }
            }
        } label: {
            Image(systemName: engine.sleepTimer == .off ? "moon.zzz" : "moon.zzz.fill")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(engine.sleepTimer == .off ? .white.opacity(0.7) : .white)
        }
        .accessibilityLabel(engine.sleepTimer == .off ? "Таймер сна" : "Таймер сна включён")
    }

    private var cancelButton: some View {
        Button("Выключить таймер", role: .destructive) { engine.cancelSleepTimer() }
    }
}
