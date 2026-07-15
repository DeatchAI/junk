//
//  AppearanceSettings.swift
//  lazzy
//
//  User-configurable appearance settings with Solid/Gradient modes
//

import SwiftUI

/// Appearance mode: solid colors, glassy, or gradient
enum AppearanceMode: String, CaseIterable {
  case solid = "Solid"  // Pure solid colors, no glass effect
  case glassy = "Glassy"  // Glass/blur effect with opacity
}

/// User appearance settings stored in UserDefaults
struct AppearanceSettings {

  // MARK: - Keys
  private enum Keys {
    static let mode = "appearance_mode"
    static let preset = "appearance_preset"
    static let backgroundColor = "appearance_bg_color"
    static let foregroundColor = "appearance_fg_color"
    static let accentColor = "appearance_accent_color"
    static let borderRadius = "appearance_border_radius"
  }

  // MARK: - Defaults (Current dark theme)
  static let defaultBackgroundColor = "#1F1F1F"  // NSColor(white: 0.12)
  static let defaultForegroundColor = "#FFFFFF"  // White
  static let defaultAccentColor = "#666666"  // Color(white: 0.4)
  static let defaultBorderRadius: Double = 12.0  // Default corner radius

  // MARK: - Properties with UserDefaults persistence

  @AppStorage(Keys.mode)
  static var mode: String = AppearanceMode.solid.rawValue

  @AppStorage(Keys.preset)
  static var presetRaw: String = ThemePreset.system.rawValue

  @AppStorage(Keys.backgroundColor)
  static var backgroundColorHex: String = defaultBackgroundColor

  @AppStorage(Keys.foregroundColor)
  static var foregroundColorHex: String = defaultForegroundColor

  @AppStorage(Keys.accentColor)
  static var accentColorHex: String = defaultAccentColor

  @AppStorage(Keys.borderRadius)
  static var borderRadius: Double = defaultBorderRadius

  // MARK: - Computed Properties

  static var preset: ThemePreset {
    get { ThemePreset(rawValue: presetRaw) ?? .system }
    set { presetRaw = newValue.rawValue }
  }

  // MARK: - Computed Properties

  static var appearanceMode: AppearanceMode {
    get { AppearanceMode(rawValue: mode) ?? .solid }
    set { mode = newValue.rawValue }
  }

  // MARK: - Reset

  static func resetToDefaults() {
    accentColorHex = defaultAccentColor
    borderRadius = defaultBorderRadius
  }
}

// MARK: - Color Extensions for Hex Conversion

extension Color {
  /// Initialize Color from hex string (supports #RRGGBB and #RRGGBBAA)
  init(hex: String) {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)

    let a: UInt64
    let r: UInt64
    let g: UInt64
    let b: UInt64
    switch hex.count {
    case 6:  // RGB
      (r, g, b, a) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF, 255)
    case 8:  // RGBA
      (r, g, b, a) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
    default:
      (r, g, b, a) = (0, 0, 0, 255)
    }

    self.init(
      .sRGB,
      red: Double(r) / 255,
      green: Double(g) / 255,
      blue: Double(b) / 255,
      opacity: Double(a) / 255
    )
  }

  /// Convert Color to hex string
  func toHex(includeAlpha: Bool = false) -> String {
    guard let components = NSColor(self).usingColorSpace(.deviceRGB)?.cgColor.components else {
      return "#000000"
    }

    let r = Int((components[0] * 255).rounded())
    let g = Int((components.count > 1 ? components[1] : components[0]) * 255)
    let b = Int((components.count > 2 ? components[2] : components[0]) * 255)

    if includeAlpha, components.count > 3 {
      let a = Int((components[3] * 255).rounded())
      return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
    return String(format: "#%02X%02X%02X", r, g, b)
  }
}
