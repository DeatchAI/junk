import Foundation

enum CursorProviderClient {
  private static let path = "/api/providers/cursor/api-key"
  private static let loginPath = "/api/providers/cursor/login"

  static func syncSavedKey() async {
    do {
      try await setAPIKey(try CursorProviderKeychain.read())
    } catch {
      print("Could not sync the Cursor API key with the local runtime: \(error.localizedDescription)")
    }
  }

  static func setAPIKey(_ apiKey: String?) async throws {
    var request = URLRequest(url: endpoint)
    request.httpMethod = apiKey == nil ? "DELETE" : "PUT"
    ServerConfig.authorize(&request)
    if let apiKey {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONEncoder().encode(APIKeyBody(apiKey: apiKey))
    }
    request.timeoutInterval = 8
    try await send(request)
  }

  static func startLogin() async throws {
    var request = URLRequest(url: endpoint(path: loginPath))
    request.httpMethod = "POST"
    ServerConfig.authorize(&request)
    request.timeoutInterval = 8
    try await send(request)
  }

  private static func send(_ request: URLRequest) async throws {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw CursorProviderClientError.message("The local runtime returned an invalid response.")
    }
    guard (200..<300).contains(response.statusCode) else {
      let apiError = try? JSONDecoder().decode(APIErrorBody.self, from: data)
      throw CursorProviderClientError.message(apiError?.error ?? "The local runtime could not complete the Cursor request.")
    }
  }

  private static var endpoint: URL {
    endpoint(path: path)
  }

  private static func endpoint(path: String) -> URL {
    var components = URLComponents()
    components.scheme = "http"
    components.host = "127.0.0.1"
    components.port = ServerConfig.port
    components.path = path
    return components.url!
  }

  private struct APIKeyBody: Encodable {
    let apiKey: String
  }

  private struct APIErrorBody: Decodable {
    let error: String?
  }
}

private enum CursorProviderClientError: LocalizedError {
  case message(String)

  var errorDescription: String? {
    switch self {
    case .message(let message): message
    }
  }
}
