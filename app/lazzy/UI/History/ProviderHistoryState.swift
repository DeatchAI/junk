import Combine
import Foundation

/// Search and sync have their own state: a history failure must not stop an agent run.
@MainActor final class ProviderHistoryState: ObservableObject {
  @Published private(set) var isSyncing = false
  @Published private(set) var isIndexing = false
  @Published private(set) var pending = 0
  @Published private(set) var indexedChats = 0
  @Published private(set) var notices: [String] = []
  @Published private(set) var query = ""
  @Published private(set) var results: [Conversation] = []
  @Published private(set) var isSearching = false
  @Published var error: String?
  private var revision: Int?
  private var catalogRevision: Int?
  private var listNeedsRefresh = false
  private var searchID: String?
  private var searchTask: Task<Void, Never>?
  private var refreshTask: Task<Void, Never>?
  private var disconnected = false

  var statusText: String {
    if isSyncing { return "Checking your agents…" }
    if isIndexing { return "Indexing message content · \(pending) remaining" }
    return "Provider histories · Local search"
  }

  func refresh(using manager: WebSocketManager) {
    guard manager.isConnected else { error = "Reconnect to refresh provider history."; return }
    error = nil
    manager.sendRequest(ProviderHistoryRequest(type: "refresh_provider_history"), label: "refresh_provider_history")
  }

  func restoreHidden(using manager: WebSocketManager) {
    guard manager.isConnected else { return }
    manager.sendRequest(ProviderHistoryRequest(type: "restore_hidden_history"), label: "restore_hidden_history")
  }

  func search(_ text: String, using manager: WebSocketManager) {
    searchTask?.cancel(); searchID = nil
    let next = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(512))
    if query != next { results = [] }
    query = next; error = nil; isSearching = !next.isEmpty
    guard !next.isEmpty else { results = []; return }
    guard manager.isConnected else { isSearching = false; error = "Reconnect to search message content."; return }
    let id = UUID().uuidString; searchID = id
    searchTask = Task { [weak self, weak manager] in
      try? await Task.sleep(for: .milliseconds(250))
      guard !Task.isCancelled, let self, let manager, self.searchID == id else { return }
      manager.sendRequest(ProviderHistoryRequest(type: "search_conversations", requestId: id, query: next), label: "search_conversations")
      try? await Task.sleep(for: .seconds(15))
      guard !Task.isCancelled, self.searchID == id else { return }
      self.isSearching = false; self.searchID = nil; self.error = "History search timed out. Try again after reconnecting."
    }
  }

  func handle(_ event: ProviderHistoryEvent, using manager: WebSocketManager) {
    switch event.type {
    case "provider_history_status":
      if disconnected { error = nil; disconnected = false }
      isSyncing = event.syncing ?? false; isIndexing = event.indexing ?? false
      pending = event.pending ?? 0; indexedChats = event.indexedChats ?? 0; notices = event.notices ?? []
      let catalog = event.catalogRevision ?? event.revision
      if catalogRevision != catalog || catalogRevision == nil { listNeedsRefresh = true; catalogRevision = catalog }
      guard revision != event.revision || revision == nil else { return }
      revision = event.revision
      guard listNeedsRefresh || !query.isEmpty else { return }
      guard refreshTask == nil else { return }
      refreshTask = Task { [weak self, weak manager] in
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled, let self, let manager else { return }
        if self.listNeedsRefresh { self.listNeedsRefresh = false; manager.refreshHistoryListing() }
        if !self.query.isEmpty { self.search(self.query, using: manager) }
        self.refreshTask = nil
      }
    case "history_search_results":
      guard event.requestId == searchID, event.query == query else { return }
      results = event.conversations ?? []; isSearching = false
      searchTask?.cancel(); searchID = nil
    case "history_error":
      error = event.error ?? "Provider history is unavailable."; isSearching = false
      searchTask?.cancel(); searchID = nil
    default: break
    }
  }

  func connectionLost() {
    searchTask?.cancel(); refreshTask?.cancel(); searchTask = nil; refreshTask = nil
    searchID = nil; revision = nil; catalogRevision = nil; listNeedsRefresh = false
    isSearching = false; isSyncing = false; isIndexing = false; disconnected = true
    error = "Runtime disconnected. Cached chats are kept; reconnect to refresh or continue."
  }
}
