import Foundation

struct ActionMCPOption: Identifiable, Hashable {
  let id: String
  let serverId: String
  let name: String
  let systemImage: String
  let detail: String
}

func actionMCPOptions(from servers: [MCPServer], composioIntegrations: [ComposioIntegration] = []) -> [ActionMCPOption] {
  let builtIn = [
    ActionMCPOption(
      id: "detach-browser-tools",
      serverId: "detach-browser-tools",
      name: "Browser",
      systemImage: "globe",
      detail: "Use your connected Chrome profile"
    ),
    ActionMCPOption(
      id: "detach-macos-tools",
      serverId: "detach-macos-tools",
      name: "macOS",
      systemImage: "macwindow",
      detail: "Control native macOS apps"
    ),
    ActionMCPOption(
      id: "detach-secrets-tools",
      serverId: "detach-secrets-tools",
      name: "Secrets",
      systemImage: "lock.fill",
      detail: "Use saved credentials with Touch ID"
    ),
  ]

  let connectedServers = servers
    .filter { server in
      server.enabled
        && (server.status?.connected ?? true)
        && !builtIn.contains(where: { $0.id == server.id })
    }

  let composioServer = connectedServers.first {
    $0.name.localizedCaseInsensitiveContains("Composio")
  }
  let connectedComposioIntegrations = composioIntegrations
    .filter { $0.connected && !$0.name.localizedCaseInsensitiveContains("Composio") }

  let custom = connectedServers
    .filter { server in
      server.id != composioServer?.id || connectedComposioIntegrations.isEmpty
    }
    .map { server in
      ActionMCPOption(
        id: server.id,
        serverId: server.id,
        name: server.name,
        systemImage: server.name.localizedCaseInsensitiveContains("Composio")
          ? "link.circle"
          : "server.rack",
        detail: server.status?.tools?.isEmpty == false
          ? "\(server.status?.tools?.count ?? 0) tools"
          : "\(server.transport.uppercased()) MCP server"
      )
    }

  let composioOptions: [ActionMCPOption]
  if let composioServer, !connectedComposioIntegrations.isEmpty {
    composioOptions = connectedComposioIntegrations.map { integration in
      ActionMCPOption(
        id: "composio:\(integration.id)",
        serverId: composioServer.id,
        name: integration.name,
        systemImage: composioSystemImage(for: integration),
        detail: "Use \(integration.name) through Composio"
      )
    }
  } else {
    composioOptions = []
  }

  return builtIn + custom + composioOptions
}

private func composioSystemImage(for integration: ComposioIntegration) -> String {
  switch integration.id.lowercased() {
  case "gmail":
    return "envelope.fill"
  case "github":
    return "chevron.left.forwardslash.chevron.right"
  case "slack":
    return "bubble.left.and.bubble.right.fill"
  case "googlecalendar", "google_calendar":
    return "calendar"
  default:
    return "puzzlepiece.extension"
  }
}
