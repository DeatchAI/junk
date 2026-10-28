//
//  ThemeManager.swift
//  lazzy
//
//  Observable singleton that provides dynamic theme colors based on user appearance settings
//

import Combine
import SwiftUI

/// Centralized theme manager that provides reactive theme colors
class ThemeManager: ObservableObject {

  static let shared = ThemeManager()

  // MARK: - Published Properties (reactive to AppStorage changes)

  @Published var mode: AppearanceMode = AppearanceSettings.appearanceMode
  @Published var preset: ThemePreset = AppearanceSettings.preset  // New property
  @Published var backgroundColorHex: String = AppearanceSettings.backgroundColorHex
  @Published var foregroundColorHex: String = AppearanceSettings.foregroundColorHex
  @Published var accentColorHex: String = AppearanceSettings.accentColorHex
  @Published var borderRadius: Double = AppearanceSettings.borderRadius
  @Published var glassTranslucency: Double = AppearanceSettings.glassTranslucency
  @Published var fontName: String = "Geist-Regular"

  private var cancellables = Set<AnyCancellable>()

  private init() {
    // Sync with UserDefaults changes
    NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
      .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
      .sink { [weak self] _ in
        self?.refreshFromSettings()
      }
      .store(in: &cancellables)
  }

  /// Refresh all values from AppearanceSettings
  func refreshFromSettings() {
    mode = AppearanceSettings.appearanceMode
    preset = AppearanceSettings.preset
    backgroundColorHex = AppearanceSettings.backgroundColorHex
    foregroundColorHex = AppearanceSettings.foregroundColorHex
    accentColorHex = AppearanceSettings.accentColorHex
    borderRadius = AppearanceSettings.borderRadius
    glassTranslucency = AppearanceSettings.glassTranslucency
  }

  // MARK: - Computed Color Properties

  var backgroundColor: Color {
    backgroundColor(for: preset)
  }

  func backgroundColor(for preset: ThemePreset) -> Color {
    // Check static themes first
    if let theme = appThemes.first(where: { $0.id == preset }) {
      return theme.backgroundColor
    }

    // Handle dynamic/special cases
    switch preset {
    case .system:
      return Color(nsColor: .windowBackgroundColor)
    // case .personalized:
    //   return Color(nsColor: .windowBackgroundColor)
    case .custom:
      return Color(hex: backgroundColorHex)
    default:
      return Color(nsColor: .windowBackgroundColor)
    }
  }

  var foregroundColor: Color {
    foregroundColor(for: preset)
  }

  func foregroundColor(for preset: ThemePreset) -> Color {
    // Check static themes first
    if let theme = appThemes.first(where: { $0.id == preset }) {
      return theme.foregroundColor
    }

    switch preset {
    case .system:
      return Color(nsColor: .labelColor)
    case .custom:
      return Color(hex: foregroundColorHex)
    default:
      return .white
    }
  }

  /// Alias for foregroundColor (for text)
  var textColor: Color {
    foregroundColor
  }

  var accentColor: Color {
    accentColor(for: preset)
  }

  func accentColor(for preset: ThemePreset) -> Color {
    // Check static themes first
    if let theme = appThemes.first(where: { $0.id == preset }) {
      return theme.accentColor
    }

    switch preset {
    case .system:
      return Color(nsColor: .controlAccentColor)
    // case .personalized:
    //   return Color(
    //     nsColor: NSColor.currentControlTint == .graphiteControlTint
    //       ? .systemGray : .controlAccentColor)
    case .custom:
      return Color(hex: accentColorHex)
    default:
      return Color(nsColor: .controlAccentColor)
    }
  }

  var secondaryTextColor: Color {
    textColor.opacity(0.6)
  }

  // MARK: - Computed Fills

  /// Select the color scheme whose primary text has the stronger black or white contrast.
  var surfaceColorScheme: ColorScheme? {
    guard preset != .system,
      let color = NSColor(backgroundColor).usingColorSpace(.sRGB) else { return nil }
    let brightness = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
    return brightness < 0.179 ? .dark : .light
  }

  /// Solid background for non-glass modes
  var solidBackground: Color {
    backgroundColor
  }

  // MARK: - Derived Colors

  /// Sidebar color (slightly lighter than background)
  var sidebarColor: Color {
    Color(hex: backgroundColorHex).opacity(0.9)
  }

  /// Input background (slightly lighter than main background)
  var inputBackgroundColor: Color {
    if mode == .liquidGlass { return controlBackgroundColor }
    return Color(nsColor: NSColor(Color(hex: backgroundColorHex)).withAlphaComponent(0.1))
  }

  /// Local controls share their containing glass instead of adding another optical layer.
  var controlBackgroundColor: Color {
    textColor.opacity(mode == .liquidGlass ? 0.04 + (1 - glassTranslucency) * 0.1 : 0.055)
  }

  /// Maximum translucency retains a light painted tint for readability and native input.
  var glassBackgroundOpacity: Double {
    1 - glassTranslucency * 0.88
  }

  /// Border color
  var borderColor: Color {
    Color(white: 0.25)
  }

  // MARK: - Font Methods

  func font(size: CGFloat) -> Font {
    return .custom(fontName, size: size)
  }

  func titleFont(size: CGFloat = 18) -> Font {
    font(size: size)
  }

  func bodyFont(size: CGFloat = 13) -> Font {
    font(size: size)
  }

  func captionFont(size: CGFloat = 11) -> Font {
    font(size: size)
  }

  // MARK: - Update Methods (called from settings UI)

  // MARK: - Update Methods (called from settings UI)

  func updatePreset(_ newPreset: ThemePreset) {
    AppearanceSettings.preset = newPreset
    preset = newPreset

    // If switching to a preset that has concrete values, we COULD update the "custom" hex backing storage
    // so that if they switch to Custom it starts from there, OR we leave Custom as their last manual edit.
    // Let's leave Custom as their last manual edit for now.
  }

  func updateMode(_ newMode: AppearanceMode) {
    AppearanceSettings.appearanceMode = newMode
    mode = newMode
  }

  func updateBackgroundColor(_ color: Color) {
    let hex = color.toHex()
    AppearanceSettings.backgroundColorHex = hex
    backgroundColorHex = hex
    // Automatically switch to custom if user manually edits color
    if preset != .custom {
      updatePreset(.custom)
    }
  }

  func updateForegroundColor(_ color: Color) {
    let hex = color.toHex()
    AppearanceSettings.foregroundColorHex = hex
    foregroundColorHex = hex
    if preset != .custom {
      updatePreset(.custom)
    }
  }

  func updateAccentColor(_ color: Color) {
    let hex = color.toHex()
    AppearanceSettings.accentColorHex = hex
    accentColorHex = hex
    if preset != .custom {
      updatePreset(.custom)
    }
  }

  func updateBorderRadius(_ radius: Double) {
    AppearanceSettings.borderRadius = radius
    borderRadius = radius
  }

  func updateGlassTranslucency(_ value: Double) {
    AppearanceSettings.glassTranslucency = value
    glassTranslucency = AppearanceSettings.glassTranslucency
  }

  func resetToDefaults() {
    AppearanceSettings.resetToDefaults()
    refreshFromSettings()
  }
}
