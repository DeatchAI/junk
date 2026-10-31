import Foundation

@main
struct PollAutomationTests {
  @MainActor
  static func main() throws {
    var passed = 0
    func check(_ condition: @autoclosure () -> Bool, _ message: String) {
      guard condition() else { fatalError(message) }
      passed += 1
    }
    func rejects(_ action: () throws -> Void, _ message: String) {
      do { try action(); fatalError(message) } catch { passed += 1 }
    }
    func request(_ question: String = "Proceed?", _ options: [String] = ["Approve once", "Deny"]) -> PollRequest {
      PollRequest(id: UUID(), question: question, options: options)
    }
    let valid = request()
    try valid.validate()
    passed += 1
    rejects({ try request("", ["A", "B"]).validate() }, "empty question accepted")
    rejects({ try request("A\nB").validate() }, "Return in question accepted")
    rejects({ try request("A\tB").validate() }, "tab in question accepted")
    rejects({ try request("Proceed?", ["A"]).validate() }, "one option accepted")
    rejects({ try request("Proceed?", ["A", "a"]).validate() }, "ambiguous labels accepted")
    rejects({ try request("Proceed?", ["A", " B"]).validate() }, "uncommitted whitespace accepted")
    rejects({ try request("Proceed?", ["A", "B\nC"]).validate() }, "Return in option accepted")
    rejects({ try request("Proceed?", Array(repeating: "A", count: 13)).validate() }, "too many choices accepted")
    rejects({ try request(String(repeating: "A", count: 1_001)).validate() }, "overlong question accepted")

    let draft = PollDraft(comment: valid.question, options: valid.options, hasAttachment: true)
    check(draft.matches(valid), "owned draft not recognized")
    check(!PollDraft(comment: "Other", options: valid.options, hasAttachment: true).matches(valid), "foreign caption accepted")
    check(!PollDraft(comment: valid.question, options: Array(valid.options.reversed()), hasAttachment: true).matches(valid), "changed option order accepted")
    check(!PollDraft(comment: valid.question, options: valid.options, hasAttachment: false).matches(valid), "text-only draft accepted as poll")
    check(PollDraft(comment: "", options: [], hasAttachment: false).isEmpty, "empty composer not recognized")

    check(PollRecipient.isRecentMatch("mobile, RECENT, +1 (555) 555-0123", recipient: "+15555550123"), "formatted phone rejected")
    check(PollRecipient.isRecentMatch("email, RECENT, Person@example.com", recipient: "person@example.com"), "email case rejected")
    check(!PollRecipient.isRecentMatch("mobile, +1 (555) 555-0123", recipient: "+15555550123"), "non-recent contact accepted")
    check(!PollRecipient.isRecentMatch("mobile, RECENT, +1 (555) 555-0124", recipient: "+15555550123"), "wrong phone accepted")
    check(!PollRecipient.isRecentMatch("email, RECENT, person15555550123@example.com", recipient: "+15555550123"), "email digits matched phone")
    check(!PollRecipient.isRecentMatch("mobile, RECENT, arbitrary15555550123", recipient: "+15555550123"), "arbitrary label matched phone")
    check(!PollRecipient.isRecentMatch("mobile, RECENT, 123", recipient: "123"), "short non-phone accepted")

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("detach-poll-tests-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("request.json")
    try PollSendAttempt.requireUnattempted(beside: url)
    let receipt = try PollSendAttempt.reserve(beside: url, request: valid)
    check(FileManager.default.fileExists(atPath: receipt.path), "receipt missing before send")
    let before = try Data(contentsOf: receipt)
    rejects({ try PollSendAttempt.requireUnattempted(beside: url) }, "repeat run not rejected before UI work")
    rejects({ _ = try PollSendAttempt.reserve(beside: url, request: valid) }, "duplicate dispatch allowed")
    check(try! Data(contentsOf: receipt) == before, "failed retry overwrote receipt")
    let permissions = try FileManager.default.attributesOfItem(atPath: receipt.path)[.posixPermissions] as? NSNumber
    check(permissions?.intValue == 0o600, "receipt is not private")

    let other = folder.appendingPathComponent("linked.json")
    try FileManager.default.createSymbolicLink(at: other.appendingPathExtension("send-attempt"), withDestinationURL: receipt)
    rejects({ try PollSendAttempt.requireUnattempted(beside: other) }, "symlink receipt accepted")
    rejects({ _ = try PollSendAttempt.reserve(beside: other, request: valid) }, "symlink receipt followed")
    print("\(passed) poll automation checks passed; no Messages UI was touched.")
  }
}
