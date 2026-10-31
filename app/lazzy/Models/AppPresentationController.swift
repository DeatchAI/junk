import AppKit
import Combine

enum AppPresentationMode: String, CaseIterable, Identifiable {
  case menuBar
  case dock

  var id: String { rawValue }
  var title: String { self == .menuBar ? "Menu Bar" : "Dock" }
  var subtitle: String {
    self == .menuBar
      ? "Keep Detach in the menu bar."
      : "Keep Detach in the Dock. Click its icon to reopen Settings."
  }

  var activationPolicy: NSApplication.ActivationPolicy {
    self == .menuBar ? .accessory : .regular
  }
}

@MainActor
final class AppPresentationController: ObservableObject {
  static let shared = AppPresentationController()

  @Published private(set) var mode: AppPresentationMode

  private init() {
    mode = AppPresentationMode(
      rawValue: UserDefaults.standard.string(forKey: AppSettings.appPresentationModeKey) ?? ""
    ) ?? .menuBar
  }

  func select(_ mode: AppPresentationMode) {
    guard self.mode != mode else { return }
    self.mode = mode
    UserDefaults.standard.set(mode.rawValue, forKey: AppSettings.appPresentationModeKey)
    applyActivationPolicy()
  }

  func applyActivationPolicy() {
    NSApp.setActivationPolicy(mode.activationPolicy)

    guard mode == .dock else {
      NSApp.applicationIconImage = nil
      return
    }

    NSApp.applicationIconImage = NSImage(named: "DetachBrand")
    NSApp.dockTile.display()
  }
}
