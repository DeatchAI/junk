import Foundation

struct HistoryConversationResponse: Decodable {
  let conversation: Conversation
  let messages: [Message]
}

struct HistoryConversationCatalog: Decodable {
  let conversations: [Conversation]
  let offset: Int
  let hasMore: Bool
}

enum HistoryConversationLoader {
  static func request(id: String, endpoint: RuntimeEndpoint) -> URLRequest {
    request(path: "/api/history/conversation", items: [URLQueryItem(name: "id", value: id)], endpoint: endpoint)
  }

  static func catalogRequest(query: String, offset: Int = 0, endpoint: RuntimeEndpoint) -> URLRequest {
    request(path: "/api/history/conversations", items: [
      URLQueryItem(name: "query", value: query), URLQueryItem(name: "offset", value: String(offset)),
      URLQueryItem(name: "limit", value: "50"),
    ], endpoint: endpoint)
  }

  static func request(id: String, port: Int, token: String) -> URLRequest {
    request(path: "/api/history/conversation", items: [URLQueryItem(name: "id", value: id)], port: port, token: token)
  }

  static func catalogRequest(query: String, offset: Int = 0, port: Int, token: String) -> URLRequest {
    request(path: "/api/history/conversations", items: [
      URLQueryItem(name: "query", value: query), URLQueryItem(name: "offset", value: String(offset)),
      URLQueryItem(name: "limit", value: "50"),
    ], port: port, token: token)
  }

  private static func request(path: String, items: [URLQueryItem], port: Int, token: String) -> URLRequest {
    var url = URLComponents()
    url.scheme = "http"; url.host = "127.0.0.1"; url.port = port
    url.path = path
    url.queryItems = items
    var request = URLRequest(url: url.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    return request
  }

  private static func request(path: String, items: [URLQueryItem], endpoint: RuntimeEndpoint) -> URLRequest {
    var url = URLComponents()
    url.scheme = "http"; url.host = endpoint.host; url.port = endpoint.port
    url.path = path
    url.queryItems = items
    var request = URLRequest(url: url.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
    request.setValue(endpoint.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
    return request
  }

  static func load(_ request: URLRequest, id: String, using session: URLSession) async throws -> HistoryConversationResponse {
    let entry: HistoryConversationResponse = try await response(request, using: session)
    guard entry.conversation.id == id else { throw LoadError.invalidResponse }
    return entry
  }

  static func loadCatalog(_ request: URLRequest, using session: URLSession) async throws -> HistoryConversationCatalog {
    try await response(request, using: session)
  }

  private static func response<T: Decodable>(_ request: URLRequest, using session: URLSession) async throws -> T {
    let (data, response) = try await session.data(for: request)
    try Task.checkCancellation()
    guard let http = response as? HTTPURLResponse else { throw LoadError.invalidResponse }
    guard http.statusCode == 200 else {
      let detail = (try? JSONDecoder().decode(Failure.self, from: data))?.error
      throw LoadError.unavailable(detail ?? "Could not load this chat. Please try again.")
    }
    return try JSONDecoder().decode(T.self, from: data)
  }

  private struct Failure: Decodable { let error: String }

  enum LoadError: LocalizedError {
    case invalidResponse
    case unavailable(String)

    var errorDescription: String? {
      switch self {
      case .invalidResponse: return "The local runtime returned an invalid conversation. Please try again."
      case .unavailable(let detail): return detail
      }
    }
  }
}
