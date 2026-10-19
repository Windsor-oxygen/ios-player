import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackEngine.self) private var engine
    @Environment(AppPresenter.self) private var presenter
    @Environment(AppIconController.self) private var icons
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsCleanup = false

    var body: some View {
        @Bindable var settings = settings
        @Bindable var presenter = presenter

        NavigationStack(path: $presenter.settingsPath) {
            Form {
                Section("Оформление") {
                    Picker("Тема", selection: $settings.appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    NavigationLink(value: SettingsRoute.appIcon) {
                        LabeledContent("Иконка приложения") {
                            HStack(spacing: DS.Spacing.s) {
                                Text(icons.current.title)
                                AppIconPreview(option: icons.current, side: DS.Size.iconPreviewInline)
                            }
                        }
                    }
                }

                Section {
                    Picker("Перемотка", selection: $settings.skipInterval) {
                        ForEach(AppSettings.skipIntervals, id: \.self) { seconds in
                            Text("\(seconds) с").tag(seconds)
                        }
                    }
                    Picker("Экран блокировки", selection: $settings.lockScreenControls) {
                        Text("Треки ⏮ ⏭").tag(LockScreenControls.tracks)
                        Text("Перемотка ±\(settings.skipInterval) с").tag(LockScreenControls.skip)
                    }
                } header: {
                    Text("Воспроизведение")
                } footer: {
                    Text("iOS показывает на экране блокировки либо переключение треков, либо перемотку — обе пары кнопок сразу недоступны.")
                }

                Section {
                    Button("Пересканировать папку") {
                        Task { await library.refresh() }
                    }
                    .disabled(library.isRefreshing)
                    if !missingIDs.isEmpty {
                        Button("Убрать отсутствующие файлы (\(missingIDs.count))", role: .destructive) {
                            confirmsCleanup = true
                        }
                    }
                } header: {
                    Text("Библиотека")
                } footer: {
                    Text("Песен: \(library.tracks.count). Файлы лежат в «Файлы» → «На iPhone» → «Player».")
                }

                Section("О приложении") {
                    LabeledContent("Версия", value: Self.version)
                }
            }
            .navigationTitle("Настройки")
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .appIcon: AppIconPickerView()
                }
            }
            .onAppear { icons.refresh() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .onChange(of: settings.skipInterval) { engine.applyRemoteCommandSettings() }
            .onChange(of: settings.lockScreenControls) { engine.applyRemoteCommandSettings() }
            .confirmationDialog(
                "Убрать из библиотеки песни, файлов которых больше нет?",
                isPresented: $confirmsCleanup,
                titleVisibility: .visible
            ) {
                Button("Убрать", role: .destructive) {
                    library.forget(Set(missingIDs))
                }
                Button("Отмена", role: .cancel) {}
            }
        }
    }

    private var missingIDs: [UUID] {
        library.tracks.filter(\.isMissing).map(\.id)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
