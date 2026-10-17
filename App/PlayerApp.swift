import SwiftUI

@main
struct PlayerApp: App {
    @State private var container = AppContainer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container.library)
                .environment(container.downloads)
                .environment(container.importPresenter)
                .preferredColorScheme(.dark)
                .task { await container.library.refresh() }
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
                Task { await container.library.saveNow() }
            default:
                break
            }
        }
    }
}
