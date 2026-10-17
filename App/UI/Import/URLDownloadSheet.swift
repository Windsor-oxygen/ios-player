import SwiftUI

/// Загрузка аудиофайла по прямой https-ссылке.
struct URLDownloadSheet: View {
    @Environment(DownloadManager.self) private var downloads
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/song.mp3", text: $text)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($focused)
                        .onSubmit(start)
                        .disabled(downloads.phase.isBusy)
                        .accessibilityLabel("Ссылка на аудиофайл")
                } footer: {
                    Text("Нужна прямая ссылка https:// на файл MP3, M4A/AAC, ALAC, WAV, AIFF или FLAC.")
                }

                statusSection

                Section {
                    if downloads.phase.isBusy {
                        Button("Отменить загрузку", role: .destructive) {
                            downloads.cancel()
                        }
                    } else {
                        Button("Загрузить", action: start)
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("Загрузка по ссылке")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .onAppear {
                downloads.isSheetVisible = true
                focused = !downloads.phase.isBusy
            }
            .onDisappear {
                downloads.isSheetVisible = false
                downloads.reset()
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch downloads.phase {
        case .idle:
            EmptyView()
        case .downloading(let received, let expected):
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    if let expected {
                        ProgressView(value: Double(received), total: Double(max(expected, 1)))
                        Text("\(received.formatted(.byteCount(style: .file))) из \(expected.formatted(.byteCount(style: .file)))")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                        Text("Загружено \(received.formatted(.byteCount(style: .file)))")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        case .importing:
            Section {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Проверка файла…")
                }
            }
        case .finished(let fileName):
            Section {
                Label {
                    Text("Добавлено: \(fileName)")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
        case .failed(let message):
            Section {
                Label {
                    Text(message)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
        }
    }

    private func start() {
        focused = false
        downloads.start(text)
    }
}
