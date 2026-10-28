import Foundation

enum HistoryGrouping: String, CaseIterable, Identifiable {
  case agent
  case workingDirectory
  static let settingsKey = "history_grouping"
  var id: String { rawValue }
  var name: String { self == .agent ? "Agent" : "Working directory" }
  var systemImage: String { self == .agent ? "cpu" : "folder" }
}

struct HistoryProviderGroup: Identifiable {
  let id: String
  let provider: AgentProvider?
  var name: String
  let workspacePath: String?
  var conversations: [Conversation]
  var isLegacy: Bool { id == "legacy" }

  /// Preserve recency within sections; never guess the provider of legacy records.
  static func groups(_ conversations: [Conversation], matching query: String = "",
    by grouping: HistoryGrouping = .agent) -> [HistoryProviderGroup] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    var groups: [HistoryProviderGroup] = []
    for conversation in conversations.sorted(by: { $0.updated_at == $1.updated_at ? $0.id < $1.id : $0.updated_at > $1.updated_at }) {
      let provider = conversation.isLegacy ? nil : conversation.provider.flatMap(AgentProvider.init(rawValue:))
      let archive = conversation.isLegacy && grouping == .agent
      let path = conversation.workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines)
      let workspace = path.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0).standardizedFileURL.path }
      let id = archive ? "legacy" : grouping == .agent ? "agent:\(conversation.provider ?? "unknown")" : "directory:\(workspace ?? "unknown")"
      let name = archive ? "Legacy Detach" : grouping == .agent ? provider?.name ?? "Other agents"
        : workspace.map { URL(fileURLWithPath: $0).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 } ?? "No working directory"
      if !query.isEmpty && ![conversation.title ?? "Untitled", provider?.name ?? name, workspace ?? ""]
        .contains(where: { $0.localizedCaseInsensitiveContains(query) }) { continue }
      if let index = groups.firstIndex(where: { $0.id == id }) {
        groups[index].conversations.append(conversation)
      } else {
        groups.append(HistoryProviderGroup(id: id, provider: grouping == .agent ? provider : nil,
          name: name, workspacePath: grouping == .workingDirectory ? workspace : nil, conversations: [conversation]))
      }
    }
    if grouping == .workingDirectory {
      let duplicates = Dictionary(grouping: groups.filter { !$0.isLegacy && $0.workspacePath != nil }, by: \.name)
      for index in groups.indices where (duplicates[groups[index].name]?.count ?? 0) > 1 {
        let peers = duplicates[groups[index].name]!.compactMap(\.workspacePath)
        let parts = groups[index].workspacePath!.split(separator: "/")
        var length = min(2, parts.count)
        while length < parts.count && peers.filter({ $0.split(separator: "/").suffix(length).elementsEqual(parts.suffix(length)) }).count > 1 { length += 1 }
        groups[index].name = parts.suffix(length).joined(separator: "/")
      }
    }
    return groups.filter { !$0.isLegacy } + groups.filter(\.isLegacy)
  }
}
