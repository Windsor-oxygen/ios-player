import SwiftUI

/// Настройки → «Иконка приложения»: сетка вариантов с отметкой текущего.
struct AppIconPickerView: View {
    @Environment(AppIconController.self) private var icons
    @State private var changes = 0
    @ScaledMetric(relativeTo: .body) private var side = DS.Size.iconPreview

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                if !icons.supportsAlternateIcons {
                    Label("Эта версия iOS не позволяет менять иконку приложения.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: side), spacing: DS.Spacing.l)],
                    spacing: DS.Spacing.xl
                ) {
                    ForEach(AppIconController.options) { option in
                        AppIconCell(option: option, side: side, isSelected: option == icons.current) {
                            Task {
                                if await icons.select(option) { changes += 1 }
                            }
                        }
                        .disabled(icons.isChanging || !icons.supportsAlternateIcons)
                    }
                }
                Text("После выбора iOS покажет системное уведомление о смене значка — это нормально. Музыка и настройки не меняются.")
                    .font(DS.Font.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(DS.Spacing.l)
        }
        .navigationTitle("Иконка приложения")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { icons.refresh() }
        .sensoryFeedback(.success, trigger: changes)
        .alert(
            "Иконка не изменена",
            isPresented: Binding(
                get: { icons.errorMessage != nil },
                set: { if !$0 { icons.errorMessage = nil } }
            ),
            presenting: icons.errorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }
}

private struct AppIconCell: View {
    let option: AppIconOption
    let side: CGFloat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.Spacing.s) {
                AppIconPreview(option: option, side: side)
                    .overlay {
                        shape.strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(DS.Opacity.hairline),
                                           lineWidth: isSelected ? DS.Stroke.selection : DS.Stroke.hairline)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(DS.Font.badgeIcon)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                Text(option.title)
                    .font(isSelected ? DS.Font.captionEmphasized : DS.Font.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: side * DS.Radius.appIconRatio, style: .continuous)
    }
}

/// Превью иконки со скруглением как на рабочем столе.
struct AppIconPreview: View {
    let option: AppIconOption
    let side: CGFloat

    var body: some View {
        Image(option.previewName)
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side * DS.Radius.appIconRatio, style: .continuous))
            .accessibilityHidden(true)
    }
}
