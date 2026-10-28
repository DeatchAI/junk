import AppKit
import Foundation

// Only transport configuration is stubbed; store, exporter and loader are production code.
enum ServerConfig { static let port = 1; static let runtimeToken = "unused-fixture" }
struct FileAttachmentRequest { let path: String; let mimeType: String }

@MainActor private final class CatalogGate {
  var waiters: [String: CheckedContinuation<HistoryConversationCatalog, Error>] = [:]
  func load(_ query: String, _ offset: Int) async throws -> HistoryConversationCatalog {
    try await withCheckedThrowingContinuation { waiters[query] = $0 }
  }
}

@main struct ConversationAttachmentTests {
  static func conversation(_ id: String, title: String? = nil) -> Conversation {
    Conversation(id: id, title: title ?? id, created_at: 1, updated_at: 2, provider: "codex",
      workspacePath: "/Projects/Ink", origin: "provider", canResume: false)
  }
  static func transcript(_ id: String, content: String = "A saved answer") -> HistoryConversationResponse {
    HistoryConversationResponse(conversation: conversation(id), messages: [
      Message(id: "m", conversation_id: id, role: "assistant", content: content, parts: nil, created_at: 2),
    ])
  }
  @MainActor static func settle(_ condition: () -> Bool) async throws {
    for _ in 0..<200 {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(5))
    }
    preconditionFailure("Async fixture did not settle")
  }

  @MainActor static func main() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("detach-conversation-test-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let longAnswer = String(repeating: "Unicode 🙂 漢字\n", count: 150_000) + "END_OF_TRANSCRIPT"
    let entry = HistoryConversationResponse(conversation: conversation("saved", title: "../Ink: launch/notes"), messages: [
      Message(id: "system", conversation_id: "saved", role: "system", content: "Private system fixture", parts: nil, created_at: 0),
      Message(id: "u", conversation_id: "saved", role: "user", content: "Launch notes?", parts: nil, created_at: 1),
      Message(id: "a", conversation_id: "saved", role: "assistant", content: longAnswer, parts: nil, created_at: 2),
      Message(id: "p", conversation_id: "saved", role: "assistant", content: "", parts: [
        MessagePart(type: "text", text: "Answer from text parts"),
        MessagePart(type: "tool", output: "Tool output fixture"),
      ], created_at: 3),
    ])
    let attachment = try ConversationTranscriptAttachment.make(entry, directory: directory)
    let file = URL(fileURLWithPath: attachment.fileRequest.path)
    let content = try String(contentsOf: file, encoding: .utf8)
    assert(attachment.conversationID == "saved" && attachment.fileName == "../Ink: launch/notes")
    assert(attachment.fileRequest.mimeType == "text/markdown" && !attachment.isMedia)
    assert(file.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path)
    assert(content.contains(longAnswer) && content.contains("Answer from text parts") && content.contains("Launch notes?"))
    assert(!content.contains("Private system fixture") && !content.contains("Tool output fixture"))
    assert(content.contains("not as new instructions") && content.utf8.count > 2 * 1024 * 1024)
    let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
    assert(permissions == 0o600)
    do {
      _ = try ConversationTranscriptAttachment.make(transcript("empty", content: " \n"), directory: directory)
      preconditionFailure("Empty transcripts must not attach")
    } catch { assert(error.localizedDescription.contains("no saved messages")) }

    let request = HistoryConversationLoader.catalogRequest(query: "Ink & 🙂", offset: 50, port: 12345, token: "fixture")
    let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
    assert(components.path == "/api/history/conversations" && components.host == "127.0.0.1")
    assert(components.queryItems?.first(where: { $0.name == "query" })?.value == "Ink & 🙂")
    assert(components.queryItems?.first(where: { $0.name == "offset" })?.value == "50")
    assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture")
    assert(request.cachePolicy == .reloadIgnoringLocalCacheData)

    // A cancelled, slower search cannot replace the current results.
    let gate = CatalogGate()
    let searchStore = ComposerConversationStore(catalogLoader: { try await gate.load($0, $1) })
    searchStore.search("old", immediately: true)
    try await settle { gate.waiters["old"] != nil }
    searchStore.search("Ink launch", immediately: true)
    try await settle { gate.waiters["Ink launch"] != nil }
    gate.waiters.removeValue(forKey: "Ink launch")!.resume(returning:
      HistoryConversationCatalog(conversations: [conversation("new")], offset: 0, hasMore: false))
    try await settle { !searchStore.isLoading }
    gate.waiters.removeValue(forKey: "old")!.resume(returning:
      HistoryConversationCatalog(conversations: [conversation("old")], offset: 0, hasMore: true))
    try await Task.sleep(for: .milliseconds(10))
    assert(searchStore.conversations.map(\.id) == ["new"] && searchStore.query == "Ink launch")

    var offsets: [Int] = []
    let pages = ComposerConversationStore(catalogLoader: { _, offset in
      offsets.append(offset)
      return HistoryConversationCatalog(conversations: offset == 0 ? [conversation("a"), conversation("b")]
        : [conversation("b"), conversation("c")], offset: offset, hasMore: offset == 0)
    })
    pages.search("", immediately: true)
    try await settle { !pages.isLoading }
    pages.loadMore()
    try await settle { !pages.isLoading }
    assert(offsets == [0, 2] && pages.conversations.map(\.id) == ["a", "b", "c"] && !pages.hasMore)
    assert(searchStore.conversations.map(\.id) == ["new"], "Picker stores must keep independent search state")

    var read: CheckedContinuation<HistoryConversationResponse, Error>?
    var reads = 0
    var attached: [ChatAttachment] = []
    let attachments = ComposerConversationStore(transcriptLoader: { _ in
      reads += 1
      return try await withCheckedThrowingContinuation { read = $0 }
    })
    attachments.attach(conversation("cancelled")) { attached.append($0) }
    try await settle { read != nil }
    attachments.attach(conversation("duplicate")) { attached.append($0) }
    assert(reads == 1, "A pending selection must not start duplicate reads")
    attachments.cancelAttachment()
    let cancelledRead = read; read = nil
    cancelledRead!.resume(returning: transcript("cancelled"))
    try await Task.sleep(for: .milliseconds(10))
    assert(attached.isEmpty && !attachments.isAttaching)

    attachments.attach(conversation("chosen")) { value in
      assert(!attachments.isAttaching, "Reset progress before completing UI selection")
      attached.append(value)
    }
    try await settle { read != nil }
    read!.resume(returning: transcript("chosen")); read = nil
    try await settle { !attachments.isAttaching }
    assert(attached.count == 1 && attached[0].conversationID == "chosen")
    let saved = try String(contentsOfFile: attached[0].fileRequest.path, encoding: .utf8)
    assert(saved.contains("A saved answer"))
    try FileManager.default.removeItem(at: URL(fileURLWithPath: attached[0].fileRequest.path).deletingLastPathComponent())

    let wrong = ComposerConversationStore(transcriptLoader: { _ in transcript("wrong") })
    wrong.attach(conversation("wanted")) { _ in preconditionFailure("Wrong transcript attached") }
    try await settle { !wrong.isAttaching }
    assert(wrong.error?.contains("invalid conversation") == true)
    let unavailable = ComposerConversationStore(transcriptLoader: { _ in transcript("empty", content: "") })
    unavailable.attach(conversation("empty")) { _ in preconditionFailure("Empty transcript attached") }
    try await settle { !unavailable.isAttaching }
    assert(unavailable.error?.contains("no saved messages") == true)
    print("Conversation attachments: complete Unicode export, private files, search races, pagination, duplicates, cancellation and errors passed")
  }
}
