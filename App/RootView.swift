import SwiftUI

struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackEngine.self) private var engine
    @Environment(AppPresenter.self) private var presenter

    var body: some View {
        @Bindable var presenter = presenter

        TabView {
            Tab("Песни", systemImage: "music.note") { SongsView().miniPlayerInset() }
            Tab("Альбомы", systemImage: "square.stack") { AlbumsView().miniPlayerInset() }
            Tab("Исполнители", systemImage: "music.mic") { ArtistsView().miniPlayerInset() }
            Tab("Плейлисты", systemImage: "music.note.list") { PlaylistsView().miniPlayerInset() }
        }
        .overlay(alignment: .top) { messageBanner }
        .fullScreenCover(isPresented: $presenter.showsNowPlaying) {
            NowPlayingView()
        }
        .sheet(isPresented: $presenter.showsSettings) {
            SettingsView()
        }
        .fileImporter(
            isPresented: $presenter.showsFilePicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await library.importFiles(urls) }
            case .failure(let error):
                library.notice = error.localizedDescription
            }
        }
        .sheet(isPresented: $presenter.showsDownloadSheet) {
            URLDownloadSheet()
        }
        .alert(
            library.lastReport.map(ImportReportText.title) ?? "",
            isPresented: Binding(
                get: { library.lastReport != nil },
                set: { if !$0 { library.lastReport = nil } }
            ),
            presenting: library.lastReport
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { report in
            Text(ImportReportText.message(report))
        }
        .alert(
            "Внимание",
            isPresented: Binding(
                get: { library.notice != nil },
                set: { if !$0 { library.notice = nil } }
            ),
            presenting: library.notice
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { notice in
            Text(notice)
        }
    }

    /// Короткие сообщения движка («Сыграет следующей», ошибки воспроизведения).
    @ViewBuilder
    private var messageBanner: some View {
        if let message = engine.message {
            Text(message)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 8)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}
