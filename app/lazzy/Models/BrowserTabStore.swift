import Combine
import Foundation

private struct BrowserCommandResponse: Decodable {
  let ok: Bool
  let result: BrowserCommandResult?
  let error: String?
}

private struct BrowserCommandResult: Decodable {
  let value: [BrowserTab]
}

@MainActor
final class BrowserTabStore: ObservableObject {
  @Published private(set) var tabs: [BrowserTab] = []
  @Published private(set) var isLoading = false
  @Published private(set) var errorMessage: String?

  private var requestTask: Task<Void, Never>?

  deinit {
    requestTask?.cancel()
  }

  func refresh() {
    guard !isLoading else { return }

    isLoading = true
    errorMessage = nil
    requestTask = Task { @MainActor [weak self] in
      do {
        let tabs = try await Self.fetchTabs()
        guard !Task.isCancelled else { return }
        self?.tabs = tabs.filter(\.isWebTab)
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled else { return }
        self?.errorMessage = error.localizedDescription
      }
      self?.isLoading = false
    }
  }

  private enum StoreError: LocalizedError {
    case runtimeUnavailable
    case invalidResponse
    case commandFailed(String)

    var errorDescription: String? {
      switch self {
      case .runtimeUnavailable:
        return "The local runtime is not ready yet."
      case .invalidResponse:
        return "Chrome returned an invalid tabs response."
      case .commandFailed(let message):
        return message
      }
    }
  }

  private nonisolated static func fetchTabs() async throws -> [BrowserTab] {
    guard ServerConfig.isServerReady else {
      throw StoreError.runtimeUnavailable
    }

    var components = URLComponents()
    components.scheme = "http"
    components.host = "127.0.0.1"
    components.port = ServerConfig.port
    components.path = "/api/browser/command"
    guard let url = components.url else { throw StoreError.invalidResponse }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 8
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    ServerConfig.authorize(&request)
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "command": "browser.list_tabs",
      "payload": [:] as [String: String],
    ])

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw StoreError.invalidResponse
    }

    let decoded = try JSONDecoder().decode(BrowserCommandResponse.self, from: data)
    guard decoded.ok else {
      throw StoreError.commandFailed(decoded.error ?? "Could not read Chrome tabs.")
    }
    guard (200..<300).contains(httpResponse.statusCode), let result = decoded.result else {
      throw StoreError.invalidResponse
    }
    return result.value
  }
}
