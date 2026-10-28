import Combine
import Foundation

struct HistoryCacheStatus: Decodable {
  let enabled: Bool
  let cachedChats: Int
  let cachedMessages: Int
  let bytes: Int
}

@MainActor final class HistoryCacheSettings: ObservableObject {
  @Published private(set) var status: HistoryCacheStatus?
  @Published private(set) var isBusy = false
  @Published private(set) var error: String?
  @Published private(set) var notice: String?

  func load() async { await request() }
  func setEnabled(_ enabled: Bool) async { await request(body: ["enabled": enabled]) }
  func clear() async {
    await request(body: ["clear": true])
    if error == nil { notice = "Cached message text cleared. Reopening chats or refreshing history can rebuild it." }
  }

  private func request(body: [String: Bool]? = nil) async {
    guard !isBusy else { return }
    isBusy = true
    error = nil
    notice = nil
    defer { isBusy = false }
    var components = URLComponents()
    components.scheme = "http"; components.host = "127.0.0.1"; components.port = ServerConfig.port
    components.path = "/api/history/cache"
    var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
    request.setValue("Bearer \(ServerConfig.runtimeToken)", forHTTPHeaderField: "Authorization")
    if let body {
      request.httpMethod = "POST"
      request.httpBody = try? JSONEncoder().encode(body)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw NSError(domain: "HistoryCache", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Could not update the local cache. Reconnect Detach and try again."])
      }
      status = try JSONDecoder().decode(HistoryCacheStatus.self, from: data)
    } catch { self.error = error.localizedDescription }
  }
}
