import AppKit
import SwiftUI

/// Shared semantic colors for native code and SwiftUI chrome, tuned for the app's background.
struct GitReviewPalette {
  let isDark: Bool

  init(background: NSColor) {
    let color = background.usingColorSpace(.sRGB) ?? .black
    isDark = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722 < 0.45
  }

  var addition: NSColor { color(dark: 0x79CE91, light: 0x237A3B) }
  var deletion: NSColor { color(dark: 0xEF8790, light: 0xC13445) }
  var modified: NSColor { color(dark: 0xE7B16C, light: 0xA46217) }
  var blue: NSColor { color(dark: 0x86BDED, light: 0x286DAD) }
  var purple: NSColor { color(dark: 0xC5A0E8, light: 0x8845A7) }
  var teal: NSColor { color(dark: 0x8ACBD1, light: 0x247982) }
  var rowOpacity: CGFloat { isDark ? 0.16 : 0.12 }

  func status(for file: GitFileChange) -> NSColor {
    if file.discarded == true { return .secondaryLabelColor }
    switch file.status {
    case "Added", "Untracked": return addition
    case "Deleted": return deletion
    case "Renamed": return blue
    default: return modified
    }
  }

  func icon(for file: GitFileChange) -> NSColor {
    switch (file.name as NSString).pathExtension.lowercased() {
    case "swift", "json", "yml", "yaml", "toml", "plist": return modified
    case "ts", "tsx", "js", "jsx", "md": return blue
    case "css", "scss", "png", "jpg", "jpeg", "gif", "webp", "heic": return purple
    case "sh", "bash", "zsh": return addition
    default: return teal
    }
  }

  private func color(dark: Int, light: Int) -> NSColor {
    let hex = isDark ? dark : light
    return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
      green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
  }
}

extension ThemeManager {
  var gitReviewPalette: GitReviewPalette { GitReviewPalette(background: NSColor(solidBackground)) }
}

struct GitChangeCounts: View {
  let additions: Int
  let deletions: Int
  var binary = false
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    HStack(spacing: 7) {
      if binary { Text("Binary").foregroundStyle(theme.secondaryTextColor) }
      else {
        Text("+\(additions)").foregroundStyle(Color(nsColor: theme.gitReviewPalette.addition))
        Text("−\(deletions)").foregroundStyle(Color(nsColor: theme.gitReviewPalette.deletion))
      }
    }.font(.system(size: 10, weight: .medium, design: .monospaced))
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(binary ? "Binary file" : "\(additions) additions, \(deletions) deletions")
  }
}
