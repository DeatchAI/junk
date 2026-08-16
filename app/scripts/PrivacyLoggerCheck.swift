import Foundation

@main
struct PrivacyLoggerCheck {
  static func main() {
    let samples = [
      ("Authorization: Bearer launch-secret-token", "launch-secret-token"),
      (#"{"prompt":"summarize my private notes"}"#, "summarize my private notes"),
      ("saved at /Users/example/Documents/private.txt", "/Users/example/Documents/private.txt"),
      ("signed in as person@example.com", "person@example.com"),
      ("credential=correct-horse-battery-staple", "correct-horse-battery-staple"),
    ]

    for (index, sample) in samples.enumerated() {
      let (input, sensitiveValue) = sample
      let output = PrivacyRedactor.redact(input)
      guard !output.contains(sensitiveValue) else {
        FileHandle.standardError.write(Data("Privacy logger failed sample \(index + 1).\n".utf8))
        Foundation.exit(1)
      }
    }
  }
}
