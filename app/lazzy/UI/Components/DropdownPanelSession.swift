import AppKit

/// One menu per parent window, with nested menu dismissal kept in sync.
@MainActor
final class DropdownPanelSession {
  static let shared = DropdownPanelSession()

  private struct Entry {
    weak var panel: NSPanel?
    weak var parent: NSWindow?
    let dismiss: () -> Void
  }
  private var entries: [Entry] = []

  func activate(_ panel: NSPanel, parent: NSWindow, dismiss: @escaping () -> Void) {
    let previous = entries.filter { $0.parent === parent && $0.panel !== panel }
    for entry in previous { entry.dismiss() }
    entries.removeAll { $0.panel == nil || $0.panel === panel }
    entries.append(Entry(panel: panel, parent: parent, dismiss: dismiss))
  }

  func remove(_ panel: NSPanel) {
    let descendants = entries.filter { $0.parent === panel }
    entries.removeAll { $0.panel == nil || $0.panel === panel }
    for entry in descendants { entry.dismiss() }
  }
}
