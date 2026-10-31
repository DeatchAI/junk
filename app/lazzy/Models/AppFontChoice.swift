import AppKit
import SwiftUI

enum AppFontChoice: String, CaseIterable, Identifiable {
  case system = "System"
  case systemMonospaced = "System-Monospaced"
  case geist = "Geist-Regular"
  case inter = "Inter-Regular"
  case cursorDisplay = "CURSORDisplay-Medium"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .system: return "System"
    case .systemMonospaced: return "System Mono"
    case .geist: return "Geist"
    case .inter: return "Inter"
    case .cursorDisplay: return "Cursor Display"
    }
  }

  func font(size: CGFloat) -> Font {
    switch self {
    case .system:
      return .system(size: size)
    case .systemMonospaced:
      return .system(size: size, design: .monospaced)
    case .geist, .inter, .cursorDisplay:
      return .custom(rawValue, size: size)
    }
  }

  func nsFont(size: CGFloat) -> NSFont {
    switch self {
    case .system:
      return NSFont.systemFont(ofSize: size)
    case .systemMonospaced:
      return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    case .geist, .inter, .cursorDisplay:
      return NSFont(name: rawValue, size: size) ?? NSFont.systemFont(ofSize: size)
    }
  }

  var bundledResource: (name: String, fileExtension: String, subdirectory: String?)? {
    switch self {
    case .geist:
      return ("normal", "otf", nil)
    case .inter:
      return ("Inter", "ttf", "Resources/Fonts")
    case .cursorDisplay:
      return ("CursorDisplay-Medium", "ttf", "Resources/Fonts")
    case .system, .systemMonospaced:
      return nil
    }
  }
}
