//
//  AppFont.swift
//  lazzy
//
//  Centralized font management for the app.
//

import SwiftUI

struct AppFont {
  static let family = "Geist-Regular"

  static func font(size: CGFloat) -> Font {
    return .custom(family, size: size)
  }

  static func nsFont(size: CGFloat) -> NSFont {
    return NSFont(name: family, size: size) ?? NSFont.systemFont(ofSize: size)
  }
}

extension Font {
  static func appFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default)
    -> Font
  {
    // Keep design support for monospaced stats, but ignore weight for our custom font
    if design == .monospaced {
      return .system(size: size, weight: weight, design: .monospaced)
    }
    return .custom(AppFont.family, size: size)
  }
}

struct AppFontModifier: ViewModifier {
  var size: CGFloat?

  func body(content: Content) -> some View {
    if let size = size {
      content.font(.custom(AppFont.family, size: size))
    } else {
      // Apply a default size if not specified,
      // but usually we want to allow the view to choose its size.
      // If we want it "global", we can just set the font family.
      content.font(.custom(AppFont.family, size: 14))  // Default size
    }
  }
}

extension View {
  func useAppFont(size: CGFloat? = nil) -> some View {
    self.modifier(AppFontModifier(size: size))
  }
}
