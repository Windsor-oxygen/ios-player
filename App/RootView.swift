import SwiftUI

struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackEngine.self) private var engine
    @Environment(AppPresenter.self) private var presenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var playerNamespace

    var body: some View {
        @Bindable var presenter = presenter

        TabView {
            Tab("Песни", systemImage: "music.note") { SongsView().miniPlayerInset(namespace: playerNamespace) }
            Tab("Альбомы", systemImage: "square.stack") { AlbumsView().miniPlayerInset(namespace: playerNamespace) }
            Tab("Исполнители", systemImage: "music.mic") { ArtistsView().miniPlayerInset(namespace: playerNamespace) }
            Tab("Плейлисты", systemImage: "music.note.list") { PlaylistsView().miniPlayerInset(namespace: playerNamespace) }
        }
        .animation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion), value: engine.currentTrack == nil)
        .overlay(alignment: .top) {
            if !presenter.showsNowPlaying { MessageBanner(message: engine.message) }
        }
        .sensoryFeedback(trigger: library.lastReport) { _, report in
            guard let report else { return nil }
            return report.failures.isEmpty ? .success : .warning
        }
        .onChange(of: engine.message) { _, message in
            // VoiceOver зачитывает всплывающие сообщения.
            if let message { AccessibilityNotification.Announcement(message).post() }
        }
        .fullScreenCover(isPresented: $presenter.showsNowPlaying) {
            NowPlayingView()
                .nowPlayingTransition(namespace: playerNamespace, reduceMotion: reduceMotion)
        }
        .sheet(isPresented: $presenter.showsSettings, onDismiss: { presenter.settingsPath = [] }) {
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
}
