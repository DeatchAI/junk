import CryptoKit
import Foundation

struct MessagesPollDecision {
  enum Target: Equatable {
    case native(code: String, choice: MessagesDecisionChoices.Choice)
    case test
  }
  let id: UUID
  let target: Target
  let caption: String
  let options: [String]
  let details: String?
  let expiresAt: Date
  var requestFingerprint: String? = nil

  var request: PollRequest { .init(id: id, question: caption, options: options) }

  static func line(_ value: String) -> String {
    value.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
      .unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined()
  }

  static func make(target: Target, heading: String, question: String, options: [String],
    detail: String? = nil, lifetime: TimeInterval, requestFingerprint: String? = nil) -> MessagesPollDecision? {
    let id = UUID()
    let ref = String(id.uuidString.replacingOccurrences(of: "-", with: "").prefix(12))
    let prompt = line(question)
    let context = detail.map(line) ?? ""
    let full = [heading, prompt, context].filter { !$0.isEmpty }.joined(separator: " · ")
    let attached = full.count > 780
    let caption = attached
      ? "\(String(line(heading).prefix(180))) · \(String(prompt.prefix(380))) · Read the attached details, then choose one. [\(ref)]"
      : "\(full) · Choose one. [\(ref)]"
    let result = MessagesPollDecision(id: id, target: target, caption: caption, options: options,
      details: attached ? [heading, question, detail ?? ""].joined(separator: "\n\n") : nil,
      expiresAt: .now.addingTimeInterval(lifetime), requestFingerprint: requestFingerprint)
    return (try? result.request.validate()) == nil ? nil : result
  }
  static func fingerprint(_ parts: [String]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: parts)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

}
