import Foundation

struct FinderQuickActionDescriptor: Codable, Equatable {
  let id: String
  let title: String
  let systemImage: String?
}

enum FinderQuickActionCatalog {
  static let preferenceDomain = "app.getlazzy.finder-quick-actions"
  private static let storageKey = "finderQuickActionCatalog.v1"

  static let fallbackActions = [
    FinderQuickActionDescriptor(id: "chat", title: "Chat", systemImage: "bubble.left"),
    FinderQuickActionDescriptor(id: "screenshot", title: "Snip", systemImage: "camera.viewfinder"),
  ]

  static func load() -> [FinderQuickActionDescriptor] {
    guard let defaults = UserDefaults(suiteName: preferenceDomain),
      let data = defaults.data(forKey: storageKey),
      let actions = try? JSONDecoder().decode([FinderQuickActionDescriptor].self, from: data),
      !actions.isEmpty
    else {
      return fallbackActions
    }

    return actions
  }

  static func save(_ actions: [FinderQuickActionDescriptor]) {
    guard !actions.isEmpty,
      let defaults = UserDefaults(suiteName: preferenceDomain),
      let data = try? JSONEncoder().encode(actions)
    else {
      return
    }

    defaults.set(data, forKey: storageKey)
    defaults.synchronize()
  }
}
