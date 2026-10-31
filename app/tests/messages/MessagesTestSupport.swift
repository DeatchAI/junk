import Combine
import Foundation

@MainActor final class LicenseManager {
  static let shared = LicenseManager()
  func requireAccess() -> Bool { true }
}

@MainActor final class WebSocketManager: ObservableObject {
  @Published var isConnected = true
  @Published var isStreaming = true
  var isStoppingRun = false
  var currentConversationId: String?
  var activeChatRequest: ChatRequest?
  var stopped = 0
  var isResumingDetachedRun = false
  var resumed: ChatRequest?
  func stopStreaming() { stopped += 1; isStreaming = false; isStoppingRun = true }
  func submitChatRequest(_ request: ChatRequest) {
    resumed = request
    activeChatRequest = request
    isStreaming = true
  }
}

@MainActor final class AgentQuestionCenter {
  static let shared = AgentQuestionCenter()
  var requests: [AgentQuestionEnvelope] = []
  var submitting = Set<String>()
  var drafts: [String: [String: String]] = [:]
  var submitted: String?
  func setAnswer(_ text: String, questionID: String, requestID: String) {
    drafts[requestID, default: [:]][questionID] = text
  }
  func answer(for question: AgentQuestion, in request: AgentQuestionEnvelope) -> String {
    drafts[request.id]?[question.id] ?? ""
  }
  func submit(_ request: AgentQuestionEnvelope) {
    submitted = request.id
    submitting.insert(request.id)
  }
}

@MainActor final class FixtureMessagesRPC: MessagesRPCTransport {
  var isRunning = false
  var onMessage: (([String: Any]) -> Void)?
  var onStreamError: ((String) -> Void)?
  var onError: ((String) -> Void)?
  var calls: [(String, [String: Any])] = []
  var subscription = 0
  var holdWatch = false
  var holdSend = false
  var sendFails = false
  var statusReady = true
  var chatListResponse: [String: Any] = ["chats": []]
  var holdAccountLookup = false
  var waitingAccount: ((Result<[String: Any], Error>) -> Void)?
  var chatService = "iMessage"
  var chatOverride: [String: Any]?
  var chatIsGroup = false
  var chatParticipants = ["+14155550123"]
  var holdChatLookup = false
  var waitingChat: ((Result<[String: Any], Error>) -> Void)?
  var waitingWatch: ((Result<[String: Any], Error>) -> Void)?
  var waitingSend: ((Result<[String: Any], Error>) -> Void)?
  var sent: [String] { calls.filter { $0.0 == "send" }.compactMap { $0.1["text"] as? String } }
  func start(ready: @escaping (Result<Void, Error>) -> Void) throws {
    isRunning = true
    ready(.success(()))
  }
  func stop() { isRunning = false }
  func request(_ method: String, params: [String: Any],
    completion: @escaping (Result<[String: Any], Error>) -> Void) {
    calls.append((method, params))
    switch method {
    case "status": completion(.success(["database": ["ready": statusReady]]))
    case "chats.list":
      if holdAccountLookup { waitingAccount = completion }
      else { completion(.success(chatListResponse)) }
    case "chats.get":
      if let chatOverride { completion(.success(chatOverride)); return }
      let info: [String: Any] = ["id": params["chat_id"] as? Int ?? 0,
        "guid": "any;-;agent@example.com", "service": chatService,
        "is_group": chatIsGroup, "participants": chatParticipants]
      if holdChatLookup { waitingChat = completion }
      else { completion(.success(info)) }
    case "watch.subscribe":
      subscription += 1
      if holdWatch { waitingWatch = completion }
      else { completion(.success(["subscription": subscription])) }
    case "send":
      if holdSend { waitingSend = completion }
      else if sendFails { completion(.failure(ImsgRPCClient.RPCError.timedOut)) }
      else { completion(.success(["ok": true])) }
    default: completion(.success(["ok": true]))
    }
  }
  func emit(_ text: String, id: Int = 10, sender: String = "+14155550123",
    fromMe: Bool = false, group: Bool = false, chatID: Int = 42, subscription: Int? = nil, chatGUID: String? = nil) {
    onMessage?(["jsonrpc": "2.0", "method": "message", "params": [
      "subscription": subscription ?? self.subscription,
      "message": ["id": id, "chat_id": chatID, "sender": sender, "text": text,
        "is_from_me": fromMe, "is_group": group, "chat_guid": chatGUID ?? (group ? "any;+;group" : "any;-;agent@example.com")]
    ]])
  }
}
