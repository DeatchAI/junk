import CryptoKit
import Foundation

/// Local file references only. Provider transcripts remain owned by the provider.
/// No prompts, responses, file contents, or thumbnails are copied to this index.
enum SentMessageAttachmentStore {
  struct FileReference: Codable {
    let path: String
    let mimeType: String
    let name: String
    let conversationID: String?
    let tokenID: UUID?

    init(_ attachment: ChatAttachment) {
      path = attachment.fileRequest.path
      mimeType = attachment.fileRequest.mimeType
      name = attachment.fileName
      conversationID = attachment.conversationID
      tokenID = attachment.id
    }

    func attachment() -> ChatAttachment? {
      guard let preview = AttachmentHelper.createAttachment(from: URL(fileURLWithPath: path)) else { return nil }
      return ChatAttachment(thumbnail: preview.thumbnail,
        fileRequest: FileAttachmentRequest(path: path, mimeType: mimeType), fileName: name,
        conversationID: conversationID, hasMediaPreview: preview.hasMediaPreview, id: tokenID ?? UUID())
    }
  }

  struct Entry: Codable {
    let messageID: String?
    let ordinal: Int
    let promptHash: String
    let files: [FileReference]
  }

  static var directory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Detach", isDirectory: true)
      .appendingPathComponent("ComposerAttachments", isDirectory: true)
  }

  static func save(_ messages: [ChatMessage], conversationID: String, directory: URL = directory) {
    let url = directory.appendingPathComponent(hash(conversationID) + ".json")
    var entries = read(url)
    guard !entries.isEmpty || messages.contains(where: { !$0.attachments.isEmpty }) else { return }
    // Empty entries distinguish repeated prompts that did not include files.
    for (ordinal, message) in messages.enumerated() {
      let fingerprint = promptHash(message.userPrompt)
      entries.removeAll {
        if let savedID = $0.messageID, let currentID = message.userMessageId {
          return savedID == currentID
        }
        return $0.ordinal == ordinal && $0.promptHash == fingerprint
      }
      entries.append(Entry(messageID: message.userMessageId, ordinal: ordinal,
        promptHash: fingerprint, files: message.attachments.map(FileReference.init)))
    }
    guard !entries.isEmpty, let data = try? JSONEncoder().encode(entries) else { return }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      try data.write(to: url, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    } catch { NSLog("Could not retain composer attachment references: %@", error.localizedDescription) }
  }

  static func restore(_ messages: [ChatMessage], conversationID: String, directory: URL = directory) -> [ChatMessage] {
    let entries = read(directory.appendingPathComponent(hash(conversationID) + ".json"))
    let hasFullHistory = messages.count >= (entries.map(\.ordinal).max().map { $0 + 1 } ?? 0)
    return messages.enumerated().map { ordinal, message in
      var message = message
      let matches = entries.filter { $0.promptHash == promptHash(message.userPrompt) }
      let ordinalMatches = matches.filter { $0.ordinal == ordinal }
      let entry = entries.first { message.userMessageId != nil && $0.messageID == message.userMessageId }
        ?? (hasFullHistory && ordinalMatches.count == 1 ? ordinalMatches.first : nil)
        ?? (matches.count == 1 ? matches.first : nil)
      if let entry { message.attachments = entry.files.compactMap { $0.attachment() } }
      return message
    }
  }

  private static func read(_ url: URL) -> [Entry] {
    guard let data = try? Data(contentsOf: url) else { return [] }
    return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
  }

  private static func promptHash(_ prompt: String) -> String {
    ConversationPrompt.fingerprint(prompt)
  }

  private static func hash(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
