import SwiftUI

struct AppearanceSettingsView: View {
  @ObservedObject private var theme = ThemeManager.shared
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  private var interfaceStyleDescription: String {
    if theme.mode == .liquidGlass {
      if #available(macOS 26.0, *) { return "Native glass. Follows Reduce Transparency." }
      return "Translucent panels. Native Liquid Glass requires macOS 26."
    }
    return "Choose how app surfaces appear."
  }

  var body: some View {
    SettingsPage(title: "Appearance", subtitle: "Personalize the look of your workspace.") {
      VStack(alignment: .leading, spacing: 7) {
        SettingsSectionHeader(title: "Theme")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
          ForEach(ThemePreset.allCases) { preset in
            UnifiedThemeRow(preset: preset, isSelected: theme.preset == preset) {
              theme.updatePreset(preset)
            }
          }
        }
      }
      SettingsSection(title: "Style") {
        SettingsRow(title: "Interface style", subtitle: interfaceStyleDescription, controlWidth: 230) {
          AppSegmentedControl(selection: Binding(get: { theme.mode }, set: { theme.updateMode($0) }),
            items: AppearanceMode.allCases, title: { $0.rawValue })
        }
        if theme.mode == .liquidGlass {
          SettingsCardDivider()
          SettingsRow(title: "Translucency",
            subtitle: reduceTransparency ? "Disabled by Reduce Transparency." : "Adjust how much of the desktop shows through.") {
            HStack(spacing: 10) {
              AppSlider(value: Binding(get: { theme.glassTranslucency }, set: { theme.updateGlassTranslucency($0) }),
                title: "Translucency").disabled(reduceTransparency)
              valueLabel("\(Int((theme.glassTranslucency * 100).rounded()))%")
            }
          }
        }
        SettingsCardDivider()
        SettingsRow(title: "Corner radius", subtitle: "Roundness of windows and panels.") {
          HStack(spacing: 10) {
            AppSlider(value: Binding(get: { theme.borderRadius }, set: { theme.updateBorderRadius($0) }),
              range: 0...30, step: 1, title: "Corner radius")
            valueLabel("\(Int(theme.borderRadius)) px")
          }
        }
      }
      SettingsSection(title: "Typography") {
        SettingsRow(title: "App font", subtitle: "Used in chats, settings, and floating panels.") {
          AppSelect(title: "App font",
            selection: Binding(get: { theme.fontChoice.rawValue }, set: {
              if let choice = AppFontChoice(rawValue: $0) { theme.updateFontChoice(choice) }
            }),
            options: AppFontChoice.allCases.map { .init(title: $0.title, value: $0.rawValue) })
        }
        SettingsCardDivider()
        Text("Aa  The quick brown fox jumps over the lazy dog.")
          .font(theme.font(size: 13)).foregroundStyle(theme.secondaryTextColor)
          .lineLimit(1).padding(.horizontal, 14).padding(.vertical, 11)
      }
      SettingsSection(title: "Custom palette") {
        SettingsRow(title: "Background", subtitle: "Window and panel surfaces.") {
          AppColorControl(selection: Binding(get: { theme.backgroundColor }, set: { theme.updateBackgroundColor($0) }))
        }
        SettingsCardDivider()
        SettingsRow(title: "Text", subtitle: "Primary labels and content.") {
          AppColorControl(selection: Binding(get: { theme.foregroundColor }, set: { theme.updateForegroundColor($0) }))
        }
        SettingsCardDivider()
        SettingsRow(title: "Accent", subtitle: "Accent color for your theme.") {
          AppColorControl(selection: Binding(get: { theme.accentColor }, set: { theme.updateAccentColor($0) }))
        }
      }
      HStack {
        Spacer()
        Button("Reset appearance") { theme.resetToDefaults() }.buttonStyle(AppButtonStyle(kind: .quiet))
      }
    }
  }

  private func valueLabel(_ text: String) -> some View {
    Text(text).font(.appFont(size: 10.5, design: .monospaced))
      .foregroundStyle(theme.secondaryTextColor).frame(width: 38, alignment: .trailing)
  }
}

struct UnifiedThemeRow: View {
  let preset: ThemePreset
  let isSelected: Bool
  let action: () -> Void
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 4) {
          Circle().fill(previewTextColor.opacity(0.55)).frame(width: 5, height: 5)
          RoundedRectangle(cornerRadius: 2).fill(previewTextColor.opacity(0.16)).frame(width: 32, height: 4)
          Spacer()
          if isSelected { Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold)) }
        }
        Text(preset.displayName).font(.appFont(size: 11.5, weight: .medium))
      }
      .foregroundStyle(previewTextColor)
      .padding(11).frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
      .background(theme.backgroundColor(for: preset), in: RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(isSelected ? theme.textColor.opacity(0.6) : theme.textColor.opacity(0.12),
            lineWidth: isSelected ? 1.2 : 0.6)
      }
    }.buttonStyle(.plain)
  }

  private var previewTextColor: Color { theme.foregroundColor(for: preset) }
}

extension View {
  func cursor(_ cursor: NSCursor) -> some View {
    onHover { inside in
      if inside { cursor.push() } else { NSCursor.pop() }
    }
  }
}
