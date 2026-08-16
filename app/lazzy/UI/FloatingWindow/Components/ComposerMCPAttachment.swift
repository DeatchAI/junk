import Foundation

struct ComposerMCPAttachment: Identifiable, Hashable {
  let id: String
  let serverId: String
  let name: String
  let systemImage: String
  let detail: String

  init(id: String, serverId: String? = nil, name: String, systemImage: String, detail: String) {
    self.id = id
    self.serverId = serverId ?? id
    self.name = name
    self.systemImage = systemImage
    self.detail = detail
  }

  static let browser = ComposerMCPAttachment(
    id: "detach-browser-tools",
    name: "Browser",
    systemImage: "globe",
    detail: "Use your connected Chrome profile"
  )

  static let macOS = ComposerMCPAttachment(
    id: "detach-macos-tools",
    name: "macOS",
    systemImage: "macwindow",
    detail: "Control native macOS apps"
  )

  static let secrets = ComposerMCPAttachment(
    id: "detach-secrets-tools",
    name: "Secrets",
    systemImage: "lock.fill",
    detail: "Use saved credentials with Touch ID"
  )
}
