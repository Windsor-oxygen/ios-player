import SwiftUI

/// Кнопка «+» в панели навигации.
struct AddMusicMenu: View {
    @Environment(ImportPresenter.self) private var presenter

    var body: some View {
        Menu {
            Button {
                presenter.showsFilePicker = true
            } label: {
                Label("Из Файлов", systemImage: "folder")
            }
            Button {
                presenter.showsDownloadSheet = true
            } label: {
                Label("По ссылке", systemImage: "link")
            }
        } label: {
            Image(systemName: "plus")
                .accessibilityLabel("Добавить музыку")
        }
    }
}
