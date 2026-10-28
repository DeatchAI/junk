import CoreText
import SwiftUI

enum OnboardingWelcomeFonts {
  private static let registration: Void = {
    for name in ["CursorDisplay-Medium", "Inter"] {
      guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
      CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
  }()

  static func register() {
    _ = registration
  }

  static func display(size: CGFloat) -> Font {
    .custom("CURSORDisplay-Medium", size: size)
  }

  static func inter(size: CGFloat) -> Font {
    .custom("Inter-Regular", size: size)
  }
}
