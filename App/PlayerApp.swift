import SwiftUI

@main
struct PlayerApp: App {
    @State private var container = AppContainer.launch()
    @Environment(\.scenePhase) private var scenePhase
    /// Было ли приложение в фоне. `.active` приходит и после системных алертов
    /// (в т. ч. о смене иконки) и Пункта управления — тогда пересканировать не нужно.
    @State private var wasInBackground = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container.settings)
                .environment(container.library)
                .environment(container.playback)
                .environment(container.downloads)
                .environment(container.presenter)
                .environment(container.appIcons)
                .defaultAppStorage(container.defaults)
                .preferredColorScheme(container.settings.appearance.colorScheme)
                .tint(container.settings.accent.color)
                .task { await container.playback.restore() }
                .task { await container.library.refresh() }
                #if DEBUG
                .task { await DemoMode.present(in: container) }
                #endif
                // «Поделиться / Открыть в» из других приложений.
                .onOpenURL { url in
                    Task { await container.library.importFiles([url]) }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Файлы могли добавить через приложение «Файлы», пока мы были в фоне.
                guard wasInBackground else { return }
                wasInBackground = false
                Task { await container.library.refresh() }
            case .background:
                wasInBackground = true
                container.playback.saveState()
                // Без фоновой задачи iOS может приостановить приложение до записи на диск.
                BackgroundWork.run("save-library") { await container.library.saveNow() }
            default:
                break
            }
        }
    }
}
