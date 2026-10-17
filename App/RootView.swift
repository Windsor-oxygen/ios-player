import SwiftUI

struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(ImportPresenter.self) private var presenter

    var body: some View {
        @Bindable var presenter = presenter

        TabView {
            Tab("Песни", systemImage: "music.note") { SongsView() }
            Tab("Альбомы", systemImage: "square.stack") { AlbumsView() }
            Tab("Исполнители", systemImage: "music.mic") { ArtistsView() }
            Tab("Плейлисты", systemImage: "music.note.list") { PlaylistsView() }
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
