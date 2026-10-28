import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Для каких треков меняем обложку (один трек или весь альбом).
struct ArtworkEditTarget: Identifiable {
    let id = UUID()
    let trackIDs: [UUID]
    /// Название трека или альбома — для заголовка и превью.
    let title: String
    let isAlbum: Bool
    /// Готовая картинка — сразу экран обрезки (демо-скриншоты).
    var preselectedImage: UIImage?
}

/// «Сменить обложку»: выбор из Фото (PhotosPicker — без доступа ко всей медиатеке)
/// или из «Файлов», квадратная обрезка, сохранение. Аудиофайлы не изменяются.
struct ArtworkEditorSheet: View {
    let target: ArtworkEditTarget

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?
    @State private var showsFileImporter = false
    @State private var editingImage: UIImage?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var saves = 0

    var body: some View {
        NavigationStack {
            Group {
                if let editingImage {
                    ArtworkCropView(image: editingImage, isSaving: isWorking) { crop in
                        Task { await save(editingImage, crop: crop) }
                    }
                } else {
                    chooser
                }
            }
            .navigationTitle(target.isAlbum ? "Обложка альбома" : "Обложка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .disabled(isWorking)
                }
            }
        }
        .onAppear {
            if editingImage == nil { editingImage = target.preselectedImage }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                Task { await loadFile(url) }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert(
            "Обложка не изменена",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
            presenting: errorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .sensoryFeedback(.success, trigger: saves)
        .interactiveDismissDisabled(isWorking)
    }

    private var chooser: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.xl) {
                ArtworkView(key: currentKey, seed: placeholderSeed, size: .large, cornerRadius: DS.Radius.xl)
                    .frame(maxWidth: DS.Size.albumHeaderArtwork)
                    .dsShadow(DS.Shadow.header)
                Text(target.title)
                    .font(DS.Font.subtitle)
                    .multilineTextAlignment(.center)
                    .lineLimit(DS.LineLimit.nowPlayingTitle)
                VStack(spacing: DS.Spacing.s) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Выбрать в Фото", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        showsFileImporter = true
                    } label: {
                        Label("Выбрать в Файлах", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    if hasCustomArtwork {
                        Button(role: .destructive) {
                            Task {
                                await library.resetCustomArtwork(for: target.trackIDs)
                                dismiss()
                            }
                        } label: {
                            Label(target.isAlbum ? "Сбросить обложку альбома" : "Сбросить обложку",
                                  systemImage: "arrow.uturn.backward")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .controlSize(.large)
                .font(DS.Font.bodyEmphasized)
                .disabled(isWorking)
                if isWorking {
                    ProgressView()
                }
                Text("Фото выбирается без доступа ко всей медиатеке. Сам аудиофайл не изменяется.")
                    .font(DS.Font.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(DS.Spacing.l)
        }
    }

    private var tracks: [Track] { library.tracks(ids: target.trackIDs) }
    private var currentKey: String? { tracks.lazy.compactMap(\.displayArtworkKey).first }
    private var placeholderSeed: String { tracks.first?.id.uuidString ?? target.title }
    private var hasCustomArtwork: Bool { tracks.contains { $0.customArtworkKey != nil } }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        isWorking = true
        defer { isWorking = false; photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = CustomArtworkError.unreadableImage.errorDescription
                return
            }
            await open(data)
        } catch {
            errorMessage = CustomArtworkError.unreadableImage.errorDescription
        }
    }

    private func loadFile(_ url: URL) async {
        isWorking = true
        defer { isWorking = false }
        guard let data = await Self.read(url) else {
            errorMessage = CustomArtworkError.unreadableImage.errorDescription
            return
        }
        await open(data)
    }

    private func open(_ data: Data) async {
        guard let image = await Self.decode(data) else {
            errorMessage = CustomArtworkError.unreadableImage.errorDescription
            return
        }
        editingImage = image
    }

    private func save(_ image: UIImage, crop: CGRect) async {
        isWorking = true
        defer { isWorking = false }
        guard let jpeg = await Self.render(image, crop: crop) else {
            errorMessage = CustomArtworkError.unreadableImage.errorDescription
            return
        }
        do {
            try await library.setCustomArtwork(jpeg, for: target.trackIDs)
            saves += 1
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // Тяжёлое — вне main thread.

    private nonisolated static func read(_ url: URL) async -> Data? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }

    private nonisolated static func decode(_ data: Data) async -> UIImage? {
        ArtworkEditing.decode(data).map { UIImage(cgImage: $0) }
    }

    private nonisolated static func render(_ image: UIImage, crop: CGRect) async -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        return ArtworkEditing.render(cgImage, crop: crop)
    }
}
