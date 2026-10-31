import Foundation

@MainActor
protocol MessagesRPCTransport: AnyObject {
  var isRunning: Bool { get }
  var onMessage: (([String: Any]) -> Void)? { get set }
  var onStreamError: ((String) -> Void)? { get set }
  var onError: ((String) -> Void)? { get set }
  func start(ready: @escaping (Result<Void, Error>) -> Void) throws
  func stop()
  func request(_ method: String, params: [String: Any],
    completion: @escaping (Result<[String: Any], Error>) -> Void)
}
