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
      VStack(alignment: .leading, spacing: 10) {

        // THEME PRESETS
        VStack(alignment: .leading, spacing: 12) {
          Text("Theme")
            // .font(.appFont(size: 13, weight: .semibold))
            .font(.custom("Sick-Regular", size: 24))
            .foregroundColor(theme.textColor)

          VStack(spacing: 8) {
            ForEach(ThemePreset.allCases) { preset in
              UnifiedThemeRow(preset: preset, isSelected: theme.preset == preset) {
                theme.updatePreset(preset)
              }
            }
          }
        }

        Divider().opacity(0.6)

        // STYLE MODE
        VStack(alignment: .leading) {
          Text("Style Mode")
            .font(.appFont(size: 13, weight: .semibold))
            .foregroundColor(theme.textColor)

          HStack {
            ForEach(AppearanceMode.allCases, id: \.self) { mode in
              Button(action: {
                theme.updateMode(mode)
              }) {
                Text(mode.rawValue)
                  .foregroundColor(theme.textColor)
                  .padding(.horizontal, 10)
                  .padding(.vertical, 5)
                  .background(theme.mode == mode ? theme.accentColor : Color.clear)
                  .cornerRadius(4)
              }
              .buttonStyle(.plain)
              .controlSize(.small)
            }
          }
        }

        Divider().opacity(0.6)

        Spacer()

        // DYNAMIC COLOR SECTION
        VStack(alignment: .leading, spacing: 16) {
          labeledPicker(label: "Background Color", selection: $backgroundColor) {
            guard !isUpdatingFromPreset else { return }
            theme.updateBackgroundColor(backgroundColor)
          }

          HStack(spacing: 20) {
            labeledPicker(label: "Text Color", selection: $foregroundColor) {
              guard !isUpdatingFromPreset else { return }
              theme.updateForegroundColor(foregroundColor)
            }
            labeledPicker(label: "Accent Color", selection: $accentColor) {
              guard !isUpdatingFromPreset else { return }
              theme.updateAccentColor(accentColor)
            }
          }
        }

        Divider().opacity(0.6)

        // BORDER RADIUS
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Border Radius")
              .font(.appFont(size: 13, weight: .semibold))
              .foregroundColor(theme.textColor)
            Spacer()
            Text("\(Int(theme.borderRadius))px")
              .font(.appFont(size: 11, design: .monospaced))
              .foregroundColor(theme.secondaryTextColor)
          }
          Slider(
            value: Binding(
              get: { theme.borderRadius },
              set: { theme.updateBorderRadius($0) }
            ), in: 0...30, step: 1
          )
          .tint(theme.accentColor)
        }

        Spacer()

        // RESET
        Button(action: {
          theme.resetToDefaults()
          refreshLocalColors()
        }) {
          Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
            .font(.appFont(size: 11))
            .foregroundColor(theme.textColor)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.vertical, 20)
    // .frame(width: 320)
    .onAppear { refreshLocalColors() }
    .onChange(of: theme.preset) { _ in
      refreshLocalColors()
    }
  }

  private func labeledPicker(label: String, selection: Binding<Color>, action: @escaping () -> Void)
    -> some View
  {
    HStack(alignment: .center, spacing: 5) {
      Text(label).font(.appFont(size: 11)).foregroundColor(theme.textColor)
      Spacer()
      CustomCircularPicker(selection: selection)
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
      HStack(spacing: 12) {
        // Theme Name
        Text(preset.displayName)
          .font(.appFont(size: 14, weight: .bold))
          .foregroundColor(previewTextColor)
          .padding(.vertical, 4)

        Spacer()

        // Accent Color Indicator + Selection Checkmark
        HStack(spacing: 8) {
          Circle()
            .fill(previewAccentColor)
            .frame(width: 14, height: 14)
            .overlay(
              Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(radius: 1)

          if isSelected {
            Image(systemName: "checkmark")
              .font(.appFont(size: 12, weight: .bold))
              .foregroundColor(previewTextColor)
          }
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(previewBackgroundColor)
          .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(
            isSelected
              ? theme.accentColor : (isHovered ? theme.textColor.opacity(0.2) : Color.clear),
            lineWidth: isSelected ? 2 : 1)
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
