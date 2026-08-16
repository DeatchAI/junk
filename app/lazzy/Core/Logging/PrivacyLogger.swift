import Foundation

enum PrivacyRedactor {
  nonisolated private static let rules: [(NSRegularExpression, String)] = [
    (expression(#"(?i)(bearer\s+)[A-Za-z0-9._~+/=-]+"#), "$1<redacted>"),
    (expression(#"(?i)([?&](?:access_?token|token|api_?key|secret|password|credential)=)[^&\s]+"#), "$1<redacted>"),
    (expression(#"(?i)(\"(?:access_?token|token|api_?key|secret|password|credential|prompt|content)\"\s*:\s*\")[^\"]*(\")"#), "$1<redacted>$2"),
    (expression(#"(?i)((?:access_?token|token|api_?key|secret|password|credential|prompt|content)\s*[:=]\s*)[^,\s]+"#), "$1<redacted>"),
    (expression(#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: [.caseInsensitive]), "<email>"),
    (expression(#"(?:/Users|/private|/var|/tmp|/Volumes)/[^\s\"'<>]+"#), "<path>"),
  ]

  nonisolated static func redact(_ message: String) -> String {
    rules.reduce(message) { result, rule in
      let range = NSRange(result.startIndex..<result.endIndex, in: result)
      return rule.0.stringByReplacingMatches(in: result, range: range, withTemplate: rule.1)
    }
  }

  nonisolated private static func expression(
    _ pattern: String,
    options: NSRegularExpression.Options = []
  ) -> NSRegularExpression {
    // These patterns are app-owned constants and are exercised by the release
    // check, so a construction failure indicates a programming error.
    try! NSRegularExpression(pattern: pattern, options: options)
  }
}

/// App-wide replacement for ad-hoc console output. Release builds emit no
/// console content; Debug builds redact common secrets and personal data first.
nonisolated func print(
  _ items: Any...,
  separator: String = " ",
  terminator: String = "\n"
) {
  #if DEBUG
    let message = items.map(String.init(describing:)).joined(separator: separator)
    Swift.print(PrivacyRedactor.redact(message), terminator: terminator)
  #endif
}
