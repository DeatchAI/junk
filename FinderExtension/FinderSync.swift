import AppKit
import FinderSync

final class FinderSync: FIFinderSync {
  override init() {
    super.init()

    // Detach does not badge or watch files. Root scope only makes the explicit
    // context-menu and toolbar command available for files, folders, and apps.
    FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
  }

  override func menu(for menuKind: FIMenuKind) -> NSMenu? {
    switch menuKind {
    case .contextualMenuForItems, .toolbarItemMenu:
      guard let selectedURLs = FIFinderSyncController.default().selectedItemURLs(),
        !selectedURLs.isEmpty
      else {
        return nil
      }

      let menu = NSMenu(title: "Detach")
      let item = NSMenuItem(
        title: selectedURLs.count == 1 ? "Detach" : "Detach \(selectedURLs.count) Items",
        action: #selector(detachSelectedItems(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "Detach")
      menu.addItem(item)
      return menu

    default:
      return nil
    }
  }

  override var toolbarItemName: String {
    "Detach"
  }

  override var toolbarItemToolTip: String {
    "Open Detach for the selected Finder items"
  }

  override var toolbarItemImage: NSImage {
    let image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "Detach")
      ?? NSImage(size: NSSize(width: 18, height: 18))
    image.isTemplate = true
    return image
  }

  @objc private func detachSelectedItems(_ sender: Any?) {
    guard let selectedURLs = FIFinderSyncController.default().selectedItemURLs(),
      !selectedURLs.isEmpty
    else {
      return
    }

    var components = URLComponents()
    components.scheme = "detach"
    components.host = "finder"
    components.queryItems = selectedURLs.map {
      URLQueryItem(name: "path", value: $0.standardizedFileURL.path)
    }

    guard let url = components.url else { return }
    NSWorkspace.shared.open(url)
  }
}
