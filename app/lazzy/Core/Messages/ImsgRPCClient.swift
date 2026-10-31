import Foundation

@MainActor
final class ImsgRPCClient: MessagesRPCTransport {
  enum RPCError: LocalizedError {
    case executableMissing
    case processNotRunning
    case invalidResponse
    case timedOut
    case remote(String)

    var errorDescription: String? {
      switch self {
      case .executableMissing: "The Messages helper is missing. Reinstall or update Detach."
      case .processNotRunning: "The Messages connection is not running."
      case .invalidResponse: "The Messages helper returned an unreadable response."
      case .timedOut: "The Messages helper did not respond in time."
      case .remote(let message): message
      }
    }
  }

  private struct PendingRequest {
    let completion: (Result<[String: Any], Error>) -> Void
    let timeout: DispatchWorkItem
  }

  private var process = Process()
  private var input = Pipe()
  private var output = Pipe()
  private var buffer = Data()
  private var generation = UUID()
  private var nextID = 0
  private var pending: [Int: PendingRequest] = [:]
  private(set) var isRunning = false
  var onMessage: (([String: Any]) -> Void)?
  var onStreamError: ((String) -> Void)?
  var onError: ((String) -> Void)?

  func start(ready: @escaping (Result<Void, Error>) -> Void) throws {
    guard !isRunning else { ready(.success(())); return }
    guard let executable = Self.findExecutable() else { throw RPCError.executableMissing }

    generation = UUID()
    let session = generation
    buffer.removeAll(keepingCapacity: true)
    process = Process()
    input = Pipe()
    output = Pipe()
    process.executableURL = executable
    process.arguments = ["rpc"]
    process.standardInput = input
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    process.environment = ProcessInfo.processInfo.environment
    output.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty else { return }
      Task { @MainActor [weak self] in
        guard self?.generation == session else { return }
        self?.consume(data)
      }
    }
    process.terminationHandler = { [weak self] child in
      Task { @MainActor [weak self] in
        guard self?.generation == session else { return }
        self?.childTerminated(status: child.terminationStatus)
      }
    }
    try process.run()
    isRunning = true
    request("initialize", params: ["protocol_version": 1]) { result in
      ready(result.map { _ in () })
    }
  }

  func stop() {
    guard isRunning else { return }
    isRunning = false
    generation = UUID()
    output.fileHandleForReading.readabilityHandler = nil
    process.terminationHandler = nil
    try? input.fileHandleForWriting.close()
    process.terminate()
    failPending(RPCError.processNotRunning)
  }

  func request(
    _ method: String,
    params: [String: Any] = [:],
    completion: @escaping (Result<[String: Any], Error>) -> Void
  ) {
    guard isRunning else { completion(.failure(RPCError.processNotRunning)); return }
    nextID += 1
    let requestID = nextID
    let timeout = DispatchWorkItem { [weak self] in
      guard let self, let pending = self.pending.removeValue(forKey: requestID) else { return }
      pending.completion(.failure(RPCError.timedOut))
    }
    pending[requestID] = PendingRequest(completion: completion, timeout: timeout)
    DispatchQueue.main.asyncAfter(deadline: .now() + (method == "send" ? 45 : 12), execute: timeout)

    do {
      let object: [String: Any] = ["jsonrpc": "2.0", "id": requestID, "method": method, "params": params]
      var data = try JSONSerialization.data(withJSONObject: object)
      data.append(0x0A)
      try input.fileHandleForWriting.write(contentsOf: data)
    } catch {
      pending.removeValue(forKey: requestID)?.timeout.cancel()
      completion(.failure(error))
    }
  }

  private func consume(_ data: Data) {
    buffer.append(data)
    while let newline = buffer.firstIndex(of: 0x0A) {
      let line = buffer[..<newline]
      buffer.removeSubrange(buffer.startIndex...newline)
      guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
        onError?(RPCError.invalidResponse.localizedDescription)
        continue
      }
      receive(object)
    }
  }

  private func receive(_ object: [String: Any]) {
    if let method = object["method"] as? String, method == "message" {
      onMessage?(object)
      return
    }
    if let method = object["method"] as? String, method == "watch.overflow" {
      onStreamError?("The Messages feed fell behind. Reconnect to continue receiving commands.")
      return
    }
    guard let id = object["id"] as? Int, let request = pending.removeValue(forKey: id) else { return }
    request.timeout.cancel()
    if let error = object["error"] as? [String: Any] {
      request.completion(.failure(RPCError.remote(error["message"] as? String ?? "The Messages request failed.")))
    } else if let result = object["result"] as? [String: Any] {
      request.completion(.success(result))
    } else {
      request.completion(.failure(RPCError.invalidResponse))
    }
  }

  private func childTerminated(status: Int32) {
    guard isRunning else { return }
    isRunning = false
    output.fileHandleForReading.readabilityHandler = nil
    failPending(RPCError.remote("The imsg process exited (\(status))."))
    onError?("The Messages connection stopped. Reconnect to try again.")
  }

  private func failPending(_ error: Error) {
    let requests = pending.values
    pending.removeAll()
    requests.forEach { $0.timeout.cancel(); $0.completion(.failure(error)) }
  }

  private static func findExecutable() -> URL? {
    let executable = Bundle.main.bundleURL
      .appendingPathComponent("Contents/Helpers/Imsg/imsg")
    return FileManager.default.isExecutableFile(atPath: executable.path) ? executable : nil
  }
}
