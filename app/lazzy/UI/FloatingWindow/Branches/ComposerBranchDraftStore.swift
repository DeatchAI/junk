import CryptoKit
import Foundation

/// Private per-path drafts. Provider transcripts are never stored here.
enum ComposerBranchDraftStore {
  struct Record: Codable {
    let text: String
    let files: [SentMessageAttachmentStore.FileReference]
    let contexts: [String]
    let skills: [SkillAttachment]
    let tabs: [BrowserTabAttachment]
    let capabilities: [ComposerMCPAttachment]
    let commands: [SlashCommandAlias]
    let selectedMessage: Int?

    init(_ draft: ComposerDraft, selectedMessage: Int?) {
      text = draft.text; files = draft.attachments.map(SentMessageAttachmentStore.FileReference.init)
      contexts = draft.contexts.compactMap(\.text); skills = draft.skills; tabs = draft.browserTabs
      capabilities = draft.mcpAttachments; commands = draft.commands; self.selectedMessage = selectedMessage
    }

    var draft: ComposerDraft {
      ComposerDraft(text: text, attachments: files.compactMap { $0.attachment() },
        contexts: contexts.map { DetectedContent(type: .text, text: $0, files: nil) },
        skills: skills, browserTabs: tabs, mcpAttachments: capabilities, commands: commands)
    }
  }

  static var directory: URL {
    SentMessageAttachmentStore.directory.deletingLastPathComponent()
      .appendingPathComponent("BranchDrafts", isDirectory: true)
  }

  static func save(_ draft: ComposerDraft, conversationID: String, selectedMessage: Int?, directory: URL = directory) {
    guard !AISettings.zeroDataRetention else { return }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      let url = file(conversationID, directory: directory)
      try JSONEncoder().encode(Record(draft, selectedMessage: selectedMessage)).write(to: url, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    } catch { NSLog("Could not save the conversation draft: %@", error.localizedDescription) }
  }

  static func load(_ conversationID: String, directory: URL = directory) -> Record? {
    guard !AISettings.zeroDataRetention,
      let data = try? Data(contentsOf: file(conversationID, directory: directory)) else { return nil }
    return try? JSONDecoder().decode(Record.self, from: data)
  }

  private static func file(_ id: String, directory: URL) -> URL {
    let name = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    return directory.appendingPathComponent(name + ".json")
  }
}

struct ComposerBranchSnapshot {
  let messages: [ChatMessage]
  let draft: ComposerDraft
  let selectedMessage: Int?
  let response: String
}

struct ComposerBranchSubmission {
  let sourceID: String
  let messageIndex: Int
  let draft: ComposerDraft
}
