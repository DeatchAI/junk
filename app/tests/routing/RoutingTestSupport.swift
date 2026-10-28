import Foundation

// Isolated transport fixtures: these tests launch no runtime or signed-in provider.
enum DetachSettings {
  static let selectedAgent = "codex"
  static func permissionMode(for agent: String) -> AgentPermissionMode { .native }
}

@MainActor final class AutoRouter {
  static let shared = AutoRouter()
  var configuration = RouterConfiguration()
  var handler: ((ChatRequest) async throws -> RouterSelection)?
  func route(_ request: ChatRequest, capabilities: [AgentCapability]) async throws -> RouterSelection {
    guard let handler else { fatalError("No routing fixture installed") }
    return try await handler(request)
  }
}

@MainActor final class WebSocketManager {
  var routingTask: Task<Void, Never>?
  var routingGeneration: UUID?
  var autoRoutedChoice: RouterPreset?
  var isStreaming = false
  var isStoppingRun = false
  var isConnected = true
  var lastError: String?
  var currentResponse = ""
  var agentCapabilities: [AgentCapability] = []
  var onError: ((String) -> Void)?
  var dispatched: [ChatRequest] = []
  func dispatchChatRequest(_ request: ChatRequest) { dispatched.append(request); isStreaming = true }
}

final class RoutingURLProtocol: URLProtocol {
  static var status = 200
  static var body = Data()
  static var captured: URLRequest?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.captured = request
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Self.body)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
