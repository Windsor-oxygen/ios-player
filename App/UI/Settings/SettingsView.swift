import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsCleanup = false

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section("Оформление") {
                    Picker("Тема", selection: $settings.appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
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
                    Text("Песен: \(library.tracks.count). Файлы лежат в «Файлы» → «На iPhone» → «Плеер».")
                }

                Section("О приложении") {
                    LabeledContent("Версия", value: Self.version)
                }
            }
            .navigationTitle("Настройки")
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
                    Task { await library.delete(Set(missingIDs)) }
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
