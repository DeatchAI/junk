import Foundation

enum SettingsLaunchIntent {
  case account
  case createQuickAction
  case createWorkflow
  case connectMCP

  var settingsTab: String {
    switch self {
    case .account:
      return "account"
    case .createQuickAction:
      return "quick_actions"
    case .createWorkflow:
      return "workflows"
    case .connectMCP:
      return "mcp"
    }
  }
}

enum ComposerCommandDestination {
  case createQuickAction
  case createWorkflow
  case connectMCP

  var settingsLaunchIntent: SettingsLaunchIntent {
    switch self {
    case .createQuickAction:
      return .createQuickAction
    case .createWorkflow:
      return .createWorkflow
    case .connectMCP:
      return .connectMCP
    }
  }
}

struct SlashCommandAlias: Identifiable, Hashable {
  let id: String
  let command: String
  let title: String
  let subtitle: String
  let systemImage: String
  let replacementText: String

  static let defaults: [SlashCommandAlias] = [
    SlashCommandAlias(
      id: "explain",
      command: "explain",
      title: "Explain",
      subtitle: "Break down the selected context clearly",
      systemImage: "bolt",
      replacementText: "Explain this clearly:"
    ),
    SlashCommandAlias(
      id: "simplify",
      command: "simplify",
      title: "Simplify",
      subtitle: "Rewrite in simpler language",
      systemImage: "bolt",
      replacementText: "Simplify this:"
    ),
    SlashCommandAlias(
      id: "code-review",
      command: "code-review",
      title: "Code Review",
      subtitle: "Review for bugs, risks, and missing tests",
      systemImage: "bolt",
      replacementText: "Review this code for bugs, regressions, and missing tests:"
    ),
    SlashCommandAlias(
      id: "compact-context",
      command: "compact-context",
      title: "Compact Context",
      subtitle: "Summarize the useful context for the next turn",
      systemImage: "text.badge.checkmark",
      replacementText: "Compact the current context into a concise handoff summary:"
    ),
    SlashCommandAlias(
      id: "debug",
      command: "debug",
      title: "Debug",
      subtitle: "Trace the likely cause and propose a fix",
      systemImage: "ladybug",
      replacementText: "Debug this issue step by step:"
    ),
    SlashCommandAlias(
      id: "plan",
      command: "plan",
      title: "Plan",
      subtitle: "Make a concise implementation plan first",
      systemImage: "list.bullet.indent",
      replacementText: "Make a concise plan before implementing:"
    ),
  ]
}

enum ComposerMode: String, Codable, CaseIterable {
  case explainOnly = "explain_only"
  case planOnly = "plan_only"
  case reviewOnly = "review_only"
  case debugOnly = "debug_only"
}

struct CustomSlashCommand: Identifiable, Equatable, Codable {
  let id: String
  let command: String
  let title: String
  let subtitle: String?
  let systemImage: String?
  let replacementText: String?
  let promptInstruction: String?
  let mode: ComposerMode?
  let enabled: Bool
  let position: Int
  let isCustom: Bool
}

enum CommandOrString: Codable {
  case command(CustomSlashCommand)
  case string(String)

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let cmd = try? container.decode(CustomSlashCommand.self) {
      self = .command(cmd)
    } else if let str = try? container.decode(String.self) {
      self = .string(str)
    } else {
      throw DecodingError.typeMismatch(
        CommandOrString.self,
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Expected CustomSlashCommand or String"
        )
      )
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .command(let cmd):
      try container.encode(cmd)
    case .string(let str):
      try container.encode(str)
    }
  }
}

