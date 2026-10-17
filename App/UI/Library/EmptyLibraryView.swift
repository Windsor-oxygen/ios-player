import SwiftUI

/// Пустая библиотека: как добавить музыку.
struct EmptyLibraryView: View {
    @Environment(AppPresenter.self) private var presenter
    @Environment(LibraryStore.self) private var library

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "waveform")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                    .padding(.top, 32)

                VStack(spacing: 8) {
                    Text("Здесь пока нет музыки")
                        .font(.title2.bold())
                    Text("Добавьте песни одним из способов:")
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 16) {
                    Label("«+» → «Из Файлов» — скопировать песни с iPhone или iCloud Drive", systemImage: "folder")
                    Label("В другом приложении: «Поделиться» → «Плеер»", systemImage: "square.and.arrow.up")
                    Label("Положите файлы в «Файлы» → «На iPhone» → «Плеер»", systemImage: "iphone")
                    Label("«+» → «По ссылке» — прямая ссылка https:// на файл", systemImage: "link")
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(spacing: 8) {
                    Button {
                        presenter.showsFilePicker = true
                    } label: {
                        Label("Выбрать в Файлах", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        presenter.showsDownloadSheet = true
                    } label: {
                        Label("Загрузить по ссылке", systemImage: "link")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                if library.isRefreshing {
                    ProgressView("Добавление музыки…")
                }

                Text("Поддерживаются MP3, M4A/AAC, ALAC, WAV, AIFF и FLAC.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}
