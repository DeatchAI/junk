//
//  AppFont.swift
//  lazzy
//
//  Centralized font management for the app.
//

import AppKit
import CoreText
import SwiftUI

struct AppFont {
  private static var choice: AppFontChoice {
    AppFontChoice(rawValue: ThemeManager.shared.fontName) ?? .geist
  }

  static func font(size: CGFloat) -> Font {
    choice.font(size: size)
  }

  static func nsFont(size: CGFloat) -> NSFont {
    choice.nsFont(size: size)
  }

  static func registerBundledFonts() {
    for resource in AppFontChoice.allCases.compactMap({ $0.bundledResource }) {
      let url = Bundle.main.url(
        forResource: resource.name,
        withExtension: resource.fileExtension,
        subdirectory: resource.subdirectory
      ) ?? Bundle.main.url(forResource: resource.name, withExtension: resource.fileExtension)
      guard let url else { continue }
      _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
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
    return AppFont.font(size: size)
  }
}

struct AppFontModifier: ViewModifier {
  var size: CGFloat?
  @ObservedObject private var theme = ThemeManager.shared

  init(size: CGFloat?) {
    self.size = size
  }

  func body(content: Content) -> some View {
    content.font(theme.font(size: size ?? 14))
  }
}

extension View {
  func useAppFont(size: CGFloat? = nil) -> some View {
    self.modifier(AppFontModifier(size: size))
  }
}
