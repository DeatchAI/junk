import Foundation

@main struct HistoryTransportTests {
  struct Connection: Decodable { let port: Int; let token: String }

  static func main() async throws {
    let path = CommandLine.arguments[1]
    var configuration: Connection?
    for _ in 0..<100 {
      if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
        let value = try? JSONDecoder().decode(Connection.self, from: data) { configuration = value; break }
      try await Task.sleep(for: .milliseconds(50))
    }
    guard let configuration else { fatalError("History transport fixture did not start") }
    let session = URLSession(configuration: .ephemeral)
    defer { session.invalidateAndCancel() }
    func request(_ id: String) -> URLRequest {
      HistoryConversationLoader.request(id: id, port: configuration.port, token: configuration.token)
    }
    func socket() -> URLSessionWebSocketTask {
      let url = URL(string: "ws://127.0.0.1:\(configuration.port)/socket?token=\(configuration.token)")!
      let task = session.webSocketTask(with: url); task.resume(); return task
    }

    let oversizedSocket = socket()
    try await oversizedSocket.send(.string("{\"type\":\"large\"}"))
    var rejectedOversizedFrame = false
    do { _ = try await oversizedSocket.receive() }
    catch {
      let native = error as NSError
      assert(native.domain == NSPOSIXErrorDomain && native.code == Int(EMSGSIZE), "Unexpected baseline error: \(error)")
      rejectedOversizedFrame = true
    }
    assert(rejectedOversizedFrame, "Baseline must reproduce the native WebSocket size failure")
    oversizedSocket.cancel(with: .normalClosure, reason: nil)

    let liveSocket = socket()
    defer { liveSocket.cancel(with: .normalClosure, reason: nil) }
    let loaded = try await HistoryConversationLoader.load(request("large"), id: "large", using: session)
    let expected = "Start\n" + String(repeating: "A🙂漢字\\\"\n", count: 700_000) + "\nEND_OF_COMPLETE_HISTORY"
    assert(loaded.messages.count == 2 && loaded.messages[1].content == expected, "Entire Unicode transcript must survive")
    assert(loaded.messages[1].content.utf8.count > 8 * 1024 * 1024)
    assert(loaded.conversation.canResume == true && loaded.conversation.isProviderHistory)
    try await liveSocket.send(.string("{\"type\":\"ping\"}"))
    guard case .string(let pong) = try await liveSocket.receive() else { fatalError("Missing live socket pong") }
    assert(pong.contains("pong"), "History must not interrupt the separate live socket")

    let small = try await HistoryConversationLoader.load(request("small"), id: "small", using: session)
    assert(small.messages[1].content == "Small saved answer")
    func catalogRequest(_ query: String, offset: Int = 0) -> URLRequest {
      HistoryConversationLoader.catalogRequest(query: query, offset: offset, port: configuration.port, token: configuration.token)
    }
    let catalog = try await HistoryConversationLoader.loadCatalog(catalogRequest(""), using: session)
    assert(catalog.conversations.map(\.id) == ["small"] && catalog.hasMore && catalog.offset == 0)
    let nextPage = try await HistoryConversationLoader.loadCatalog(catalogRequest("", offset: 50), using: session)
    assert(!nextPage.hasMore && nextPage.offset == 50)
    let search = try await HistoryConversationLoader.loadCatalog(catalogRequest("Ink & 🙂"), using: session)
    assert(search.conversations.map(\.id) == ["small"] && !search.hasMore)
    var deniedCatalog = catalogRequest("")
    deniedCatalog.setValue("Bearer wrong", forHTTPHeaderField: "Authorization")
    do {
      _ = try await HistoryConversationLoader.loadCatalog(deniedCatalog, using: session)
      fatalError("Unauthenticated catalog should fail")
    } catch { assert(error.localizedDescription.contains("Unauthorized")) }
    do {
      _ = try await HistoryConversationLoader.load(request("missing"), id: "missing", using: session)
      fatalError("Missing chat should fail")
    } catch { assert(error.localizedDescription.contains("unavailable")) }
    do {
      _ = try await HistoryConversationLoader.load(request("small"), id: "different", using: session)
      fatalError("Mismatched conversation should fail")
    } catch { assert(error.localizedDescription.contains("invalid conversation")) }
    var unauthorized = request("small")
    unauthorized.setValue("Bearer wrong", forHTTPHeaderField: "Authorization")
    do {
      _ = try await HistoryConversationLoader.load(unauthorized, id: "small", using: session)
      fatalError("Unauthenticated request should fail")
    } catch { assert(error.localizedDescription.contains("Unauthorized")) }
    let slow = Task { try await HistoryConversationLoader.load(request("slow"), id: "slow", using: session) }
    try await Task.sleep(for: .milliseconds(50)); slow.cancel()
    do { _ = try await slow.value; fatalError("Cancelled history load should not complete") }
    catch { assert(error is CancellationError || (error as NSError).code == NSURLErrorCancelled) }
    print("Complete 9+ MiB history, conversation catalog/search/pagination, live socket, auth, errors and cancellation passed")
  }
}
