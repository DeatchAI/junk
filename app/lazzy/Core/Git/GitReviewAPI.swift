import Foundation

@MainActor enum GitReviewAPI {
  static func request<Value: Decodable>(_ route: String, query: [String: String] = [:],
      body: [String: Any]? = nil, endpoint: RuntimeEndpoint? = nil) async throws -> Value {
    let endpoint = endpoint ?? .local
    var components = URLComponents()
    components.scheme = "http"; components.host = endpoint.host; components.port = endpoint.port
    components.path = "/api/git/\(route)"
    components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    guard let url = components.url else { throw ReviewError(message: "Could not open this project's changes.") }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
    request.setValue(endpoint.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
    if let body {
      request.httpMethod = "POST"
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error
      throw ReviewError(message: message ?? "Project changes are unavailable. Reconnect Detach and try again.")
    }
    return try JSONDecoder().decode(Value.self, from: data)
  }

  static func review(workspace: String, runID: String?, project: Bool, conversationID: String? = nil,
                     endpoint: RuntimeEndpoint? = nil) async throws -> GitReviewResponse {
    var query = ["workspace": workspace, "scope": conversationID != nil ? "session" : project ? "project" : "task"]
    if let conversationID { query["conversation"] = conversationID }
    if let runID { query["run"] = runID }
    return try await request("review", query: query, endpoint: endpoint)
  }

  private struct Failure: Decodable { let error: String }
  struct ReviewError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }
}

extension Notification.Name {
  static let gitReviewChanged = Notification.Name("DetachGitReviewChanged")
}
