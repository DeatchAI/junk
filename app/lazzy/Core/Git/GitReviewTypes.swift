import Foundation

struct GitRepositoryInfo: Decodable, Equatable {
  let root: String
  let branch: String
}

struct GitFileChange: Decodable, Identifiable, Equatable {
  var id: String { path }
  let path: String
  let previousPath: String?
  let status: String
  let additions: Int
  let deletions: Int
  let binary: Bool
  let reason: String?
  let staged: Bool?
  let earlier: Bool?
  let discarded: Bool?
  var diff: String?
  var name: String { URL(fileURLWithPath: path).lastPathComponent }
  var parent: String { (path as NSString).deletingLastPathComponent }
  var counts: String { binary ? "Binary" : "+\(additions) −\(deletions)" }
}

struct GitTaskSummary: Decodable, Identifiable, Equatable {
  var id: String { runId }
  let runId: String
  let promptHash: String
  let messageOrdinal: Int?
  let startedAt: Int
  let completedAt: Int
  let repository: GitRepositoryInfo
  let mixed: Bool
  let notice: String?
  var files: [GitFileChange]
  let recoveryID: String?
  var counts: String {
    let remaining = files.filter { $0.discarded != true }
    if !files.isEmpty && remaining.isEmpty { return "Changes discarded" }
    return "+\(remaining.reduce(0) { $0 + $1.additions }) −\(remaining.reduce(0) { $0 + $1.deletions })"
  }
}

struct GitReviewResponse: Decodable {
  let repository: GitRepositoryInfo?
  let files: [GitFileChange]
  let task: GitTaskSummary?
  let canDiscard: Bool
  let notice: String?
  let recoveryID: String?
}

struct GitRestorePreview: Decodable, Identifiable {
  let id: String
  let paths: [String]
  let action: String
  let repository: String
  let scope: String?
  var isSession: Bool { scope == "session" }
  var isUndo: Bool { action == "undo" }
}

struct GitSnapshotSettings: Decodable {
  let enabled: Bool
  let taskCount: Int
  let recoveryCount: Int
  let bytes: Int
}

struct GitApplyResult: Decodable {
  let applied: [String]
  let failures: [String]
  let notice: String
}

struct GitTaskList: Decodable { let tasks: [GitTaskSummary] }

enum GitTaskMatcher {
  static func match(_ tasks: [GitTaskSummary], runID: String?, promptHash: String, timestamp: Int?, ordinal: Int? = nil) -> GitTaskSummary? {
    if let runID { return tasks.first { $0.runId == runID } }
    let candidates = tasks.filter { $0.promptHash == promptHash }
    if let ordinal, candidates.contains(where: { $0.messageOrdinal != nil }) {
      let exact = candidates.filter { $0.messageOrdinal == ordinal }
      return exact.count == 1 ? exact.first : nil
    }
    if let timestamp {
      return candidates.filter { abs($0.startedAt - timestamp) < 180_000 }
        .min { abs($0.startedAt - timestamp) < abs($1.startedAt - timestamp) }
    }
    return candidates.count == 1 ? candidates.first : nil
  }
}
