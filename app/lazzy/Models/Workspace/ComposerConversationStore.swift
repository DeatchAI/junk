import Combine
import Foundation

/// The attachment picker owns its searches and reads; opening a chat is a separate operation.
@MainActor final class ComposerConversationStore: ObservableObject {
  typealias CatalogLoader = (String, Int) async throws -> HistoryConversationCatalog
  typealias TranscriptLoader = (String) async throws -> HistoryConversationResponse

  @Published private(set) var conversations: [Conversation] = []
  @Published private(set) var query = ""
  @Published private(set) var isLoading = false
  @Published private(set) var hasMore = false
  @Published private(set) var error: String?
  @Published private(set) var attachingID: String?
  var isAttaching: Bool { attachingID != nil }

  private let catalogLoader: CatalogLoader
  private let transcriptLoader: TranscriptLoader
  private var listTask: Task<Void, Never>?
  private var attachmentTask: Task<Void, Never>?
  private var listID: UUID?
  private var attachmentID: UUID?
  private var nextOffset = 0

  init(catalogLoader: CatalogLoader? = nil, transcriptLoader: TranscriptLoader? = nil) {
    self.catalogLoader = catalogLoader ?? { query, offset in
      let request = HistoryConversationLoader.catalogRequest(query: query, offset: offset,
        port: ServerConfig.port, token: ServerConfig.runtimeToken)
      return try await HistoryConversationLoader.loadCatalog(request, using: .shared)
    }
    self.transcriptLoader = transcriptLoader ?? { id in
      let request = HistoryConversationLoader.request(id: id, port: ServerConfig.port, token: ServerConfig.runtimeToken)
      return try await HistoryConversationLoader.load(request, id: id, using: .shared)
    }
  }

  var contentRevision: String {
    [query, String(isLoading), attachingID ?? "", error ?? "", String(hasMore)]
      .joined(separator: "\u{1F}") + conversations.map { "\($0.id):\($0.title ?? ""): \($0.updated_at)" }.joined(separator: "\u{1F}")
  }

  func search(_ value: String, immediately: Bool = false) {
    let next = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(512))
    if query != next { conversations = [] }
    query = next
    hasMore = false
    requestPage(offset: 0, debounce: !immediately && !next.isEmpty)
  }

  func loadMore() {
    guard hasMore, !isLoading else { return }
    requestPage(offset: nextOffset, debounce: false)
  }

  func cancelSearch() {
    listTask?.cancel(); listTask = nil; listID = nil; isLoading = false
  }

  func cancelAttachment() {
    attachmentTask?.cancel(); attachmentTask = nil; attachmentID = nil; attachingID = nil
  }

  func attach(_ conversation: Conversation, onComplete: @escaping (ChatAttachment) -> Void) {
    guard !isAttaching else { return }
    let id = UUID()
    attachmentID = id; attachingID = conversation.id; error = nil
    attachmentTask = Task { [weak self] in
      guard let self else { return }
      do {
        let entry = try await transcriptLoader(conversation.id)
        try Task.checkCancellation()
        guard attachmentID == id else { return }
        guard entry.conversation.id == conversation.id else { throw HistoryConversationLoader.LoadError.invalidResponse }
        let attachment = try ConversationTranscriptAttachment.make(entry)
        attachmentTask = nil; attachmentID = nil; attachingID = nil
        onComplete(attachment)
      } catch {
        guard attachmentID == id else { return }
        if !Task.isCancelled { self.error = error.localizedDescription }
        attachmentTask = nil; attachmentID = nil; attachingID = nil
      }
    }
  }

  private func requestPage(offset: Int, debounce: Bool) {
    cancelSearch()
    let id = UUID(), value = query
    listID = id; isLoading = true; error = nil
    listTask = Task { [weak self] in
      guard let self else { return }
      do {
        if debounce { try await Task.sleep(for: .milliseconds(200)) }
        let page = try await catalogLoader(value, offset)
        try Task.checkCancellation()
        guard listID == id else { return }
        guard page.offset == offset else { throw HistoryConversationLoader.LoadError.invalidResponse }
        var seen = Set(offset == 0 ? [] : conversations.map(\.id))
        let rows = page.conversations.filter { seen.insert($0.id).inserted }
        conversations = offset == 0 ? rows : conversations + rows
        nextOffset = page.offset + page.conversations.count
        hasMore = page.hasMore && !page.conversations.isEmpty
        isLoading = false; listID = nil; listTask = nil
      } catch {
        guard listID == id else { return }
        if !Task.isCancelled { self.error = error.localizedDescription }
        isLoading = false; listID = nil; listTask = nil
      }
    }
  }
}
