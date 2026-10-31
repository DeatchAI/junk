import Foundation
import CryptoKit

struct PollRequest: Codable {
  let id: UUID
  let question: String
  let options: [String]

  func validate() throws {
    let strings = [question] + options
    guard !strings.contains(where: { $0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }),
      !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, question.count <= 1_000, !question.contains(where: \.isNewline),
      (2...12).contains(options.count),
      options.allSatisfy({ !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) &&
        !$0.contains(where: \.isNewline) && $0.count <= 120 }),
      Set(options.map { $0.lowercased() }).count == options.count else {
      throw PollUIError.unavailable("Use a single-line question of 1–1,000 characters and 2–12 distinct, single-line choices (up to 120 characters each).")
    }
  }

  var fingerprint: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try! encoder.encode(self)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

struct PollDraft: Codable, Equatable {
  let comment: String
  let options: [String]
  let hasAttachment: Bool

  func matches(_ request: PollRequest) -> Bool {
    hasAttachment && comment == request.question && options == request.options
  }

  var isEmpty: Bool { comment.isEmpty && options.isEmpty && !hasAttachment }
}

enum PollRecipient {
  static func normalize(_ value: String) -> String {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if value.contains("@") {
      let parts = value.split(separator: "@", omittingEmptySubsequences: false)
      return parts.count == 2 && parts.allSatisfy({ !$0.isEmpty && !$0.contains(where: \.isWhitespace) }) ? value : ""
    }
    let allowed = CharacterSet(charactersIn: "+0123456789 ()-.")
    guard value.unicodeScalars.allSatisfy(allowed.contains) else { return "" }
    let digits = value.filter(\.isNumber)
    guard (7...15).contains(digits.count) else { return "" }
    return digits
  }

  static func isRecentMatch(_ description: String, recipient: String) -> Bool {
    let pieces = description.components(separatedBy: ",").map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard pieces.contains("RECENT"), let address = pieces.last else { return false }
    let expected = normalize(recipient)
    return !expected.isEmpty && normalize(address) == expected
  }
}

/// Created before dispatching Return. Its presence blocks an uncertain duplicate send.
enum PollSendAttempt {
  static func requireUnattempted(beside requestURL: URL) throws {
    let path = requestURL.appendingPathExtension("send-attempt").path
    var metadata = stat()
    guard lstat(path, &metadata) != 0, errno == ENOENT else {
      throw PollUIError.unavailable("This request already has a send attempt or its receipt cannot be inspected. Check Messages before creating another request.")
    }
  }

  static func reserve(beside requestURL: URL, request: PollRequest) throws -> URL {
    let url = requestURL.appendingPathExtension("send-attempt")
    let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else {
      throw PollUIError.unavailable("A send was already attempted for this request, or its receipt cannot be created. Inspect Messages; do not retry an uncertain send.")
    }
    let data = Data("\(request.id.uuidString)\n\(request.fingerprint)\n\(Date().timeIntervalSince1970)\n".utf8)
    let written = data.withUnsafeBytes { bytes in write(descriptor, bytes.baseAddress, bytes.count) }
    let synced = fsync(descriptor)
    close(descriptor)
    guard written == data.count, synced == 0 else {
      throw PollUIError.unavailable("Could not save the send-attempt receipt. The poll was not sent.")
    }
    return url
  }
}
