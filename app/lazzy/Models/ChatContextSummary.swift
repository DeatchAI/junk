import Foundation

struct ChatContextSummary: Codable, Equatable {
  let runId: String?
  let userCharacters: Int
  let instructionCharacters: Int
  let attachmentCharacters: Int
  let fileCount: Int
  let toolServerCount: Int
  let permissionMode: String
}
