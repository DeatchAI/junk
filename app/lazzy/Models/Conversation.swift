import Foundation

struct Conversation: Codable, Identifiable {
  let id: String
  let title: String?
  let created_at: Int
  let updated_at: Int
  let provider: String?
  let workspacePath: String?
  let model: String?
  let importSource: ConversationImportSource?
  let origin: String?
  let canResume: Bool?
  let historyWarning: String?
  let searchSnippet: String?

  init(id: String, title: String?, created_at: Int, updated_at: Int,
    provider: String? = nil, workspacePath: String? = nil, model: String? = nil,
    importSource: ConversationImportSource? = nil, origin: String? = nil, canResume: Bool? = nil,
    historyWarning: String? = nil, searchSnippet: String? = nil) {
    self.id = id; self.title = title; self.created_at = created_at; self.updated_at = updated_at
    self.provider = provider; self.workspacePath = workspacePath; self.model = model; self.importSource = importSource
    self.origin = origin; self.canResume = canResume; self.historyWarning = historyWarning; self.searchSnippet = searchSnippet
  }

  var createdDate: Date { Date(timeIntervalSince1970: TimeInterval(created_at) / 1000) }
  var updatedDate: Date { Date(timeIntervalSince1970: TimeInterval(updated_at) / 1000) }
  var isProviderHistory: Bool { origin == "provider" }
  var isLegacy: Bool { !isProviderHistory }

  func named(_ title: String) -> Conversation {
    Conversation(id: id, title: title, created_at: created_at, updated_at: updated_at,
      provider: provider, workspacePath: workspacePath, model: model, importSource: importSource,
      origin: origin, canResume: canResume, historyWarning: historyWarning, searchSnippet: searchSnippet)
  }
}

struct ConversationImportSource: Codable {
  let provider: String
  let canResume: Bool
  let warning: String?
}
