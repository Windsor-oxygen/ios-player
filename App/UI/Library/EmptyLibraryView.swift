import SwiftUI

/// Пустая библиотека: иллюстрация и подсказки, как добавить музыку.
struct EmptyLibraryView: View {
    @Environment(AppPresenter.self) private var presenter
    @Environment(LibraryStore.self) private var library

    var body: some View {
        ScrollView {
            EmptyStateView(
                symbol: "waveform",
                title: "Здесь пока нет музыки",
                message: "Добавьте песни одним из способов:"
            ) {
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    Label("«+» → «Из Файлов» — скопировать песни с iPhone или iCloud Drive", systemImage: "folder")
                    Label("В другом приложении: «Поделиться» → «Player»", systemImage: "square.and.arrow.up")
                    Label("Положите файлы в «Файлы» → «На iPhone» → «Player»", systemImage: "iphone")
                    Label("«+» → «По ссылке» — прямая ссылка https:// на файл", systemImage: "link")
                }
                .font(DS.Font.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Spacing.l)
                .background(.quaternary.opacity(DS.Opacity.tertiary),
                            in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))

                VStack(spacing: DS.Spacing.s) {
                    Button {
                        presenter.showsFilePicker = true
                    } label: {
                        Label("Выбрать в Файлах", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        presenter.showsDownloadSheet = true
                    } label: {
                        Label("Загрузить по ссылке", systemImage: "link")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
                .font(DS.Font.bodyEmphasized)

                if library.isRefreshing {
                    ProgressView("Обновление библиотеки…")
                }

                Text("Поддерживаются MP3, M4A/AAC, ALAC, WAV, AIFF и FLAC.")
                    .font(DS.Font.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
