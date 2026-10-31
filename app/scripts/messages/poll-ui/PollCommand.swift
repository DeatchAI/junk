import Foundation

@main
struct PollCommand {
  @MainActor
  static func main() async {
    do {
      let args = Array(CommandLine.arguments.dropFirst())
      guard let command = args.first, ["inspect", "check", "prepare", "send", "run"].contains(command) else {
        throw PollUIError.unavailable("Usage: poll-ui.sh inspect|check | prepare|send|run --request /absolute/request.json")
      }
      guard let settings = UserDefaults(suiteName: "app.getlazzy"),
        settings.bool(forKey: "messages_remote.enabled"),
        let sender = settings.string(forKey: "messages_remote.sender"), !sender.isEmpty,
        settings.integer(forKey: "messages_remote.chat_id") > 0 else {
        throw PollUIError.unavailable("Pair your iPhone with Detach first. This prototype only uses the paired phone.")
      }
      let workflow = try PollWorkflow(recipient: sender)
      if command == "check" {
        guard args.count == 1 else { throw PollUIError.unavailable("check takes no arguments.") }
        try await workflow.ax.activate()
        try await workflow.verifyRecipient()
        try output(["status": "recipient_verified"])
        return
      }
      if command == "inspect" {
        guard args.count == 1 else { throw PollUIError.unavailable("inspect takes no arguments.") }
        try output(workflow.draft())
        return
      }
      guard args.count == 3, args[1] == "--request", args[2].hasPrefix("/") else {
        throw PollUIError.unavailable("Pass --request followed by an absolute JSON file path.")
      }
      let url = URL(fileURLWithPath: args[2])
      let request = try JSONDecoder().decode(PollRequest.self, from: Data(contentsOf: url))
      try request.validate()
      if command == "send" || command == "run" {
        try PollSendAttempt.requireUnattempted(beside: url)
      }
      switch command {
      case "prepare":
        try await workflow.prepare(request)
        try output(["status": "draft_ready", "request_id": request.id.uuidString])
      case "run":
        try await workflow.prepare(request)
        try output(await workflow.sendPrepared(request, requestURL: url))
      case "send":
        try output(await workflow.sendPrepared(request, requestURL: url))
      default: break
      }
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      FileHandle.standardError.write(Data("Poll automation stopped: \(message)\n".utf8))
      exit(1)
    }
  }

  static func output<T: Encodable>(_ result: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    FileHandle.standardOutput.write(try encoder.encode(result))
    FileHandle.standardOutput.write(Data("\n".utf8))
  }
}
