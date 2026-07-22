//
//  ThemeDefinitions.swift
//  lazzy
//
//  Vibrant & varied theme presets
//

import SwiftUI

// MARK: - Theme Presets

enum ThemePreset: String, CaseIterable, Identifiable {

  // System / user controlled
  case system = "System"
  case lazzydark = "Lazzy Dark"
  case lazzywhite = "Lazzy White"
  // case personalized = "Personalized"
  case custom = "Custom"

  // Calm / Neutral
  case midnight = "Midnight"
  case forest = "Forest"
  case ocean = "Ocean"

  // Vibrant / Fun
  case cyberpunk = "Cyberpunk"
  case vaporwave = "Vaporwave"
  case bubblegum = "Bubblegum"
  case sunburst = "Sunburst"
  case limeSoda = "Lime Soda"
  case inferno = "Inferno"

  // Experimental
  case aurora = "Aurora"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .lazzydark:
      return "Detach Dark"
    case .lazzywhite:
      return "Detach White"
    default:
      return rawValue
    }
  }
}

// MARK: - Theme Definition

struct ThemeDefinition: Identifiable {
  let id: ThemePreset
  let name: String
  let backgroundColor: Color
  let foregroundColor: Color
  let accentColor: Color
}

// MARK: - App Themes

let appThemes: [ThemeDefinition] = [

  // MARK: Calm / Neutral

  ThemeDefinition(
    id: .midnight,
    name: "Midnight",
    backgroundColor: Color(hex: "#0F1115"),
    foregroundColor: Color(hex: "#E5E7EB"),
    accentColor: Color(hex: "#6B7280")
  ),

  ThemeDefinition(
    id: .lazzydark,
    name: "Detach Dark",
    backgroundColor: Color(hex: "#0e0e0e"),
    foregroundColor: .white,
    accentColor: Color(hex: "#F64900")
  ),

  ThemeDefinition(
    id: .lazzywhite,
    name: "Detach White",
    backgroundColor: Color(hex: "#fefefe"),
    foregroundColor: .black,
    accentColor: Color(hex: "#F64900")
  ),

  ThemeDefinition(
    id: .forest,
    name: "Forest",
    backgroundColor: Color(hex: "#0F2419"),
    foregroundColor: Color(hex: "#ECFDF5"),
    accentColor: Color(hex: "#22C55E")
  ),

  ThemeDefinition(
    id: .ocean,
    name: "Ocean",
    backgroundColor: Color(hex: "#020617"),
    foregroundColor: Color(hex: "#E0F2FE"),
    accentColor: Color(hex: "#38BDF8")
  ),

  // MARK: Vibrant / Fun

  ThemeDefinition(
    id: .cyberpunk,
    name: "Cyberpunk",
    backgroundColor: Color(hex: "#0A001F"),
    foregroundColor: Color(hex: "#F8FAFC"),
    accentColor: Color(hex: "#00F5FF")
  ),

  ThemeDefinition(
    id: .vaporwave,
    name: "Vaporwave",
    backgroundColor: Color(hex: "#1B0036"),
    foregroundColor: Color(hex: "#FDF4FF"),
    accentColor: Color(hex: "#FF71CE")
  ),

  ThemeDefinition(
    id: .bubblegum,
    name: "Bubblegum",
    backgroundColor: Color(hex: "#FFE4F1"),
    foregroundColor: Color(hex: "#3B0764"),
    accentColor: Color(hex: "#EC4899")
  ),

  ThemeDefinition(
    id: .sunburst,
    name: "Sunburst",
    backgroundColor: Color(hex: "#FFF7ED"),
    foregroundColor: Color(hex: "#7C2D12"),
    accentColor: Color(hex: "#F97316")
  ),

  ThemeDefinition(
    id: .limeSoda,
    name: "Lime Soda",
    backgroundColor: Color(hex: "#ECFDF5"),
    foregroundColor: Color(hex: "#064E3B"),
    accentColor: Color(hex: "#22C55E")
  ),

  ThemeDefinition(
    id: .inferno,
    name: "Inferno",
    backgroundColor: Color(hex: "#1C0202"),
    foregroundColor: Color(hex: "#FFE4E6"),
    accentColor: Color(hex: "#EF4444")
  ),

  // MARK: Experimental (special handling in ThemeManager)
]
