import Combine
import Foundation

@MainActor final class WebSocketManager: ObservableObject {
  @Published var isConnected = true
  var isStreaming = true
  var requests: [[String: Any]] = []
  var listCount = 0
  func sendRequest<T: Encodable>(_ request: T, label: String) {
    requests.append(try! JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any])
  }
  func listConversations() { listCount += 1 }
  func refreshHistoryListing() { listCount += 1 }
}

@main struct ProviderHistoryTests {
  @MainActor static func main() async throws {
    func event(_ json: String) -> ProviderHistoryEvent { ProviderHistoryEvent.parse(Data(json.utf8))! }
    let native = try JSONDecoder().decode(Conversation.self, from: Data("""
      {"id":"native_codex","title":"Keyboard navigation","created_at":1000,"updated_at":2000,
       "provider":"codex","workspacePath":"/project","model":"small-model","origin":"provider","canResume":true,
       "searchSnippet":"Found in message content"}
      """.utf8))
    let named = native.named("Rename")
    assert(named.isProviderHistory && !named.isLegacy && named.canResume == true)
    assert(named.searchSnippet == native.searchSnippet && named.workspacePath == "/project" && named.model == "small-model")
    let legacy = Conversation(id: "legacy", title: "Old Detach chat", created_at: 10, updated_at: 3000, provider: "claude", origin: "legacy")
    let claude = Conversation(id: "claude", title: "Claude work", created_at: 20, updated_at: 100, provider: "claude", origin: "provider", canResume: false)
    let groups = HistoryProviderGroup.groups([legacy, claude, native])
    assert(groups.map(\.name) == ["Codex", "Claude", "Legacy Detach"])
    assert(groups.last?.provider == nil && groups.last?.conversations.first?.id == legacy.id)
    assert(HistoryProviderGroup.groups([native, claude], matching: "project").count == 1)
    let sameProject = Conversation(id: "other-agent", title: "Another agent in the project", created_at: 10, updated_at: 1500,
      provider: "claude", workspacePath: "/project/", origin: "provider")
    let duplicateName = Conversation(id: "same-folder-name", title: "A different folder", created_at: 10, updated_at: 50,
      provider: "pi", workspacePath: "/elsewhere/project", origin: "provider")
    let workingGroups = HistoryProviderGroup.groups([native, sameProject, duplicateName, claude], by: .workingDirectory)
    assert(workingGroups.first?.conversations.map(\.id) == [native.id, sameProject.id], "The same directory groups across agents and normalizes trailing slashes")
    assert(workingGroups.first?.provider == nil && workingGroups.first?.workspacePath == "/project")
    assert(workingGroups.map(\.name).contains("No working directory"))
    assert(workingGroups.filter { !$0.isLegacy && $0.workspacePath != nil }.map(\.name) == ["project", "elsewhere/project"])
    let legacyFolders = HistoryProviderGroup.groups([legacy, claude], by: .workingDirectory)
    assert(legacyFolders.count == 1 && legacyFolders[0].name == "No working directory")
    assert(legacyFolders[0].conversations.map(\.id) == [legacy.id, claude.id], "Keep archived chats without adding a non-directory separator")
    assert(HistoryGrouping.allCases.map(\.rawValue) == ["agent", "workingDirectory"])
    assert(HistoryProviderGroup.groups([sameProject, native], by: .agent).count == 2)
    func paging(bottom: CGFloat = 550, height: CGFloat = 500, hasMore: Bool = true, loading: Bool = false,
      connected: Bool = true, searching: Bool = false, presented: Bool = true) -> Bool {
      HistoryPaginationState(bottomY: bottom, viewportHeight: height, count: 500, hasMore: hasMore,
        isLoading: loading, isConnected: connected, isSearching: searching, isPresented: presented).shouldLoadMore
    }
    assert(paging() && paging(bottom: 200), "Near-bottom scrolling and short pages should load more")
    assert(!paging(bottom: 900) && !paging(bottom: .infinity) && !paging(bottom: -10) && !paging(height: 0))
    assert(!paging(hasMore: false) && !paging(loading: true) && !paging(connected: false))
    assert(!paging(searching: true) && !paging(presented: false), "No pagination during search or after dismissal")

    let manager = WebSocketManager(); let state = ProviderHistoryState()
    state.handle(event("""
      {"type":"provider_history_status","syncing":true,"indexing":true,"pending":5,"indexedChats":30,"revision":1,"notices":["Amp: sign in required"]}
      """), using: manager)
    assert(state.isSyncing && state.isIndexing && state.pending == 5 && state.notices.count == 1)
    try await Task.sleep(for: .milliseconds(450))
    assert(manager.listCount == 1)
    state.handle(event("{\"type\":\"provider_history_status\",\"revision\":2,\"catalogRevision\":1,\"indexing\":true}"), using: manager)
    try await Task.sleep(for: .milliseconds(450))
    assert(manager.listCount == 1, "Indexing progress must not reset loaded history pages")
    state.search("first", using: manager)
    state.search("body phrase", using: manager)
    try await Task.sleep(for: .milliseconds(300))
    assert(manager.requests.count == 1 && manager.requests.last?["query"] as? String == "body phrase")
    let id = manager.requests.last!["requestId"] as! String
    state.handle(event("""
      {"type":"history_search_results","requestId":"stale","query":"first","conversations":[]}
      """), using: manager)
    assert(state.isSearching)
    state.handle(event("""
      {"type":"history_search_results","requestId":"\(id)","query":"body phrase","conversations":[
       {"id":"body-hit","title":"Unrelated title","created_at":1,"updated_at":2,"provider":"pi","origin":"provider","searchSnippet":"A body phrase hit"}]}
      """), using: manager)
    assert(!state.isSearching && state.results.first?.id == "body-hit")
    assert(HistoryProviderGroup.groups(state.results).first?.name == "Pi", "Body search hits must not be filtered out by title again")
    state.handle(event("{\"type\":\"history_error\",\"error\":\"Provider offline\"}"), using: manager)
    assert(state.error == "Provider offline" && manager.isStreaming, "History errors must not interrupt a run")
    state.search("", using: manager); assert(state.results.isEmpty && !state.isSearching)
    state.refresh(using: manager); assert(manager.requests.last?["type"] as? String == "refresh_provider_history")
    state.restoreHidden(using: manager); assert(manager.requests.last?["type"] as? String == "restore_hidden_history")
    state.connectionLost(); assert(!state.isSyncing && !state.isIndexing && state.error != nil)
    state.handle(event("{\"type\":\"provider_history_status\",\"revision\":1}"), using: manager)
    assert(state.error == nil)
    try await Task.sleep(for: .milliseconds(450))
    assert(manager.listCount == 2, "Reconnect must restart history refreshes")
    assert(ProviderHistoryEvent.parse(Data("{\"type\":\"unrelated\"}".utf8)) == nil)
    print("History directory grouping, duplicate folder names, infinite scrolling guards, search, recovery and run isolation checks passed")
  }
}
