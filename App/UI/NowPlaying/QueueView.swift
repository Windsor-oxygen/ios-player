import SwiftUI

/// Очередь: текущий трек и «Далее» с перестановкой и удалением.
struct QueueView: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let track = engine.currentTrack {
                    Section("Сейчас играет") {
                        TrackRow(track: track)
                    }
                }
                Section {
                    ForEach(Array(engine.queue.upcoming)) { entry in
                        Button {
                            engine.jump(to: entry.id)
                        } label: {
                            if let track = library.tracksByID[entry.trackID] {
                                TrackRow(track: track)
                            } else {
                                Text("Песня удалена").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onMove { engine.moveUpcoming(fromOffsets: $0, toOffset: $1) }
                    .onDelete { engine.removeUpcoming(atOffsets: $0) }
                } header: {
                    HStack {
                        Text("Далее")
                        Spacer()
                        QueueModeButtons()
                    }
                } footer: {
                    if engine.queue.upcoming.isEmpty {
                        Text("Дальше ничего нет. Добавляйте песни через долгое нажатие → «Играть следующим» или «В конец очереди».")
                    }
                }
            }
            .navigationTitle("Очередь")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}

/// Кнопки shuffle и repeat.
struct QueueModeButtons: View {
    @Environment(PlaybackEngine.self) private var engine

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            Button {
                engine.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .modeStyle(active: engine.queue.isShuffled)
            }
            .accessibilityLabel("Перемешать")
            .accessibilityValue(engine.queue.isShuffled ? "Включено" : "Выключено")

            Button {
                engine.cycleRepeatMode()
            } label: {
                Image(systemName: engine.queue.repeatMode == .one ? "repeat.1" : "repeat")
                    .modeStyle(active: engine.queue.repeatMode != .off)
            }
            .accessibilityLabel("Повтор")
            .accessibilityValue(repeatDescription)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: engine.queue.isShuffled)
        .sensoryFeedback(.selection, trigger: engine.queue.repeatMode)
    }

    private var repeatDescription: String {
        switch engine.queue.repeatMode {
        case .off: String(localized: "Выключен")
        case .all: String(localized: "Повторять очередь")
        case .one: String(localized: "Повторять трек")
        }
    }
}

private extension Image {
    /// Активный режим — заливка акцентом; значок цвета фона (читается в обеих темах).
    func modeStyle(active: Bool) -> some View {
        font(DS.Font.modeIcon)
            .frame(width: DS.Size.modeButton.width, height: DS.Size.modeButton.height)
            .foregroundStyle(active ? Color(uiColor: .systemBackground) : Color.secondary)
            .background(active ? Color.accentColor : Color.clear,
                        in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
            .frame(minWidth: DS.Size.tapTarget, minHeight: DS.Size.tapTarget)
            .contentShape(Rectangle())
    }
}
