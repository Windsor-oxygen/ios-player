import SwiftUI

@main
struct PlayerApp: App {
    @State private var container = AppContainer.launch()
    @Environment(\.scenePhase) private var scenePhase

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
                Task { await container.library.refresh() }
            case .background:
                container.playback.saveState()
                Task { await container.library.saveNow() }
            default:
                break
            }
        }
    }
}
