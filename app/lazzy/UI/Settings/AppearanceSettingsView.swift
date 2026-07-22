import SwiftUI

// MARK: - Fully Fixed Circular Picker
struct CustomCircularPicker: View {
  @Binding var selection: Color
  var supportsOpacity: Bool = false
  var borderColor: Color = .white.opacity(0.3)
  var size: CGFloat = 24  // Increased size for better ergonomics

  var body: some View {
    ZStack {
      // 1. Visual Circle (The part the user sees)
      Circle()
        .fill(selection)
        .frame(width: size, height: size)
        .overlay(
          Circle()
            .stroke(borderColor, lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)

      // 2. The Native Picker
      // We scale it up and mask it to force the "center" hit-zone
      ColorPicker("", selection: $selection, supportsOpacity: supportsOpacity)
        .labelsHidden()
        .scaleEffect(2.0)  // Scale up to make the clickable area huge
        .frame(width: size, height: size)
        .clipped()  // Cut off the invisible parts outside the circle
        .opacity(0.015)
        .allowsHitTesting(true)
    }
    .frame(width: size, height: size)
    .contentShape(Circle())
    .cursor(.pointingHand)  // Changes cursor to hand for better UX
  }
}

// MARK: - Main Appearance View
struct AppearanceSettingsView: View {
  @ObservedObject private var theme = ThemeManager.shared

  @State private var backgroundColor: Color = .black
  @State private var foregroundColor: Color = .white
  @State private var accentColor: Color = .blue
  @State private var isUpdatingFromPreset: Bool = false  // Prevents onChange loop

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        SettingsPageHeader(
          title: "Appearance",
          subtitle: "Make Detach feel at home on your Mac with a preset or a custom palette."
        )

        VStack(alignment: .leading, spacing: 10) {
          SettingsSectionHeader(
            title: "Theme",
            subtitle: "Choose a starting point for every Detach window."
          )

          LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            ForEach(ThemePreset.allCases) { preset in
              UnifiedThemeRow(preset: preset, isSelected: theme.preset == preset) {
                theme.updatePreset(preset)
              }
            }
          }
        }

        VStack(alignment: .leading, spacing: 10) {
          SettingsSectionHeader(title: "Style")

          SettingsCard {
            SettingsRow(
              title: "Interface style",
              subtitle: "Use a filled or translucent window treatment"
            ) {
              HStack(spacing: 3) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                  Button {
                    theme.updateMode(mode)
                  } label: {
                    Text(mode.rawValue)
                      .font(.appFont(size: 10.5, weight: .medium))
                      .foregroundColor(theme.mode == mode ? theme.backgroundColor : theme.textColor.opacity(0.75))
                      .padding(.horizontal, 10)
                      .padding(.vertical, 6)
                      .background(theme.mode == mode ? theme.accentColor : Color.clear)
                      .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                  }
                  .buttonStyle(.plain)
                }
              }
              .padding(3)
              .background(theme.textColor.opacity(0.055))
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            SettingsCardDivider()

            SettingsRow(
              title: "Corner radius",
              subtitle: "Adjust the roundness of cards and windows"
            ) {
              HStack(spacing: 10) {
                Slider(
                  value: Binding(
                    get: { theme.borderRadius },
                    set: { theme.updateBorderRadius($0) }
                  ), in: 0...30, step: 1
                )
                .tint(theme.accentColor)
                .frame(width: 150)

                Text("\(Int(theme.borderRadius)) px")
                  .font(.appFont(size: 10.5, design: .monospaced))
                  .foregroundColor(theme.secondaryTextColor)
                  .frame(width: 38, alignment: .trailing)
              }
            }
          }
        }

        VStack(alignment: .leading, spacing: 10) {
          SettingsSectionHeader(
            title: "Custom palette",
            subtitle: "Fine-tune the current theme. Changes are applied immediately."
          )

          SettingsCard {
            colorRow(title: "Background", subtitle: "Window and panel background", selection: $backgroundColor) {
              guard !isUpdatingFromPreset else { return }
              theme.updateBackgroundColor(backgroundColor)
            }

            SettingsCardDivider()

            colorRow(title: "Text", subtitle: "Primary labels and content", selection: $foregroundColor) {
              guard !isUpdatingFromPreset else { return }
              theme.updateForegroundColor(foregroundColor)
            }

            SettingsCardDivider()

            colorRow(title: "Accent", subtitle: "Selections, buttons, and focus states", selection: $accentColor) {
              guard !isUpdatingFromPreset else { return }
              theme.updateAccentColor(accentColor)
            }
          }
        }

        HStack {
          Spacer()
          Button(action: {
            theme.resetToDefaults()
            refreshLocalColors()
          }) {
            Label("Reset appearance", systemImage: "arrow.counterclockwise")
              .font(.appFont(size: 11, weight: .medium))
              .foregroundColor(theme.secondaryTextColor)
          }
          .buttonStyle(.plain)
        }

        Spacer(minLength: 20)
      }
      .padding(.bottom, 24)
    }
    .onAppear { refreshLocalColors() }
    .onChange(of: theme.preset) { _ in
      refreshLocalColors()
    }
  }

  private func colorRow(
    title: String,
    subtitle: String,
    selection: Binding<Color>,
    action: @escaping () -> Void
  ) -> some View {
    SettingsRow(title: title, subtitle: subtitle) {
      CustomCircularPicker(selection: selection, size: 26)
        .onChange(of: selection.wrappedValue) { action() }
    }
  }

  private func refreshLocalColors() {
    isUpdatingFromPreset = true
    backgroundColor = theme.backgroundColor
    foregroundColor = theme.foregroundColor
    accentColor = theme.accentColor
    // Use a small delay to ensure onChange has fired before re-enabling
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      isUpdatingFromPreset = false
    }
  }
}

// MARK: - Unified Theme Row
struct UnifiedThemeRow: View {
  let preset: ThemePreset
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovered = false
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          HStack(spacing: 4) {
            Circle().fill(previewAccentColor).frame(width: 8, height: 8)
            Circle().fill(previewTextColor.opacity(0.55)).frame(width: 8, height: 8)
          }
          Spacer()
          Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(isSelected ? previewAccentColor : previewTextColor.opacity(0.35))
        }

        RoundedRectangle(cornerRadius: 3)
          .fill(previewTextColor.opacity(0.18))
          .frame(width: 52, height: 4)

        Text(preset.displayName)
          .font(.appFont(size: 11.5, weight: .semibold))
          .foregroundColor(previewTextColor)
      }
      .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
      .padding(12)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(previewBackgroundColor)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(
            isSelected
              ? theme.accentColor : (isHovered ? theme.textColor.opacity(0.22) : theme.textColor.opacity(0.08)),
            lineWidth: isSelected ? 1.5 : 0.7)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
  }

  // Theme Colors for Preview
  var previewBackgroundColor: Color {
    ThemeManager.shared.backgroundColor(for: preset)
  }

  var previewTextColor: Color {
    ThemeManager.shared.foregroundColor(for: preset)
  }

  var previewAccentColor: Color {
    ThemeManager.shared.accentColor(for: preset)
  }
}

// Extension to make it feel more like a button on macOS
extension View {
  func cursor(_ cursor: NSCursor) -> some View {
    onHover { inside in
      if inside { cursor.push() } else { NSCursor.pop() }
    }
  }
}
