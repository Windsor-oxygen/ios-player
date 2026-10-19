import SwiftUI

/// Ряд образцов акцентного цвета с отметкой выбранного.
struct AccentPicker: View {
    @Binding var selection: AccentTheme

    @ScaledMetric(relativeTo: .body) private var side = DS.Size.accentSwatch

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: side), spacing: DS.Spacing.m)], spacing: DS.Spacing.m) {
            ForEach(AccentTheme.allCases) { theme in
                Button {
                    selection = theme
                } label: {
                    Circle()
                        .fill(theme.color)
                        .frame(width: side, height: side)
                        .overlay {
                            if theme == selection {
                                Image(systemName: "checkmark")
                                    .font(DS.Font.captionEmphasized)
                                    .foregroundStyle(Color(uiColor: .systemBackground))
                            }
                        }
                        .padding(DS.Stroke.selection)
                        .overlay {
                            Circle()
                                .strokeBorder(theme == selection ? theme.color : .clear, lineWidth: DS.Stroke.hairline * DS.Stroke.ringScale)
                        }
                        .accentGlow(theme.glows, color: theme.color)
                        .frame(minWidth: DS.Size.tapTarget, minHeight: DS.Size.tapTarget)
                        .contentShape(Circle())
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityLabel(theme.title)
                .accessibilityAddTraits(theme == selection ? [.isButton, .isSelected] : .isButton)
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}
