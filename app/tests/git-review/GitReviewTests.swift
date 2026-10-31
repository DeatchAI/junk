import Foundation

@main struct GitReviewTests {
  static func main() throws {
    let data = Data("""
      {"runId":"first","promptHash":"hash","startedAt":1000000,"completedAt":1000020,
       "repository":{"root":"/project","branch":"main"},"mixed":false,"files":[]}
      """.utf8)
    let first = try JSONDecoder().decode(GitTaskSummary.self, from: data)
    let second = try JSONDecoder().decode(GitTaskSummary.self, from: Data(String(decoding: data, as: UTF8.self)
      .replacingOccurrences(of: "first", with: "second").replacingOccurrences(of: "1000000", with: "1100000").utf8))
    precondition(GitTaskMatcher.match([first, second], runID: "first", promptHash: "other", timestamp: nil)?.runId == "first")
    precondition(GitTaskMatcher.match([first, second], runID: "missing", promptHash: "hash", timestamp: nil) == nil)
    precondition(GitTaskMatcher.match([first, second], runID: nil, promptHash: "hash", timestamp: nil) == nil)
    precondition(GitTaskMatcher.match([first, second], runID: nil, promptHash: "hash", timestamp: 1100010)?.runId == "second")
    precondition(GitTaskMatcher.match([first], runID: nil, promptHash: "hash", timestamp: 9000000) == nil)
    let ordinalData = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"promptHash\"", with: "\"messageOrdinal\":0,\"promptHash\"")
    let ordinal = try JSONDecoder().decode(GitTaskSummary.self, from: Data(ordinalData.utf8))
    precondition(GitTaskMatcher.match([ordinal], runID: nil, promptHash: "hash", timestamp: 9000000, ordinal: 0)?.runId == "first")
    precondition(GitTaskMatcher.match([ordinal], runID: nil, promptHash: "hash", timestamp: 1000000, ordinal: 1) == nil)
    let rows = GitDiffLines.parse("@@ -4,2 +4,3 @@\n unchanged\n-removed\n+added\n+more\n\\ No newline at end of file")
    precondition(rows[1].oldLine == 4 && rows[1].newLine == 4)
    precondition(rows[2].oldLine == 5 && rows[2].newLine == nil && rows[2].kind == .deletion)
    precondition(rows[3].newLine == 5 && rows[3].oldLine == nil && rows[3].kind == .addition)
    precondition(rows[4].newLine == 6 && rows[5].kind == .metadata)
    precondition(GitDiffLines.parse("Binary file changed.")[0].kind == .metadata)
    let aligned = GitDiffLines.aligned("diff --git a/test b/test\n--- a/test\n+++ b/test\n@@ -4,3 +4,4 @@\n unchanged\n-old\n+new\n+extra\n tail\n")
    precondition(aligned.count == 5 && aligned[0].section != nil)
    precondition(aligned[2].before?.text == "-old" && aligned[2].after?.text == "+new")
    precondition(aligned[3].before == nil && aligned[3].after?.newLine == 6)
    precondition(aligned[4].before?.oldLine == 6 && aligned[4].after?.newLine == 7)
    let deleted = GitDiffLines.aligned("@@ -1,2 +0,0 @@\n-one\n-two")
    precondition(deleted.count == 3 && deleted[2].before?.oldLine == 2 && deleted[2].after == nil)
    let files = ["app/UI/Composer.swift", "app/UI/Changes.swift", "README.md", "web/page.tsx"].map {
      GitFileChange(path: $0, previousPath: nil, status: "Modified", additions: 1, deletions: 1,
        binary: false, reason: nil, staged: nil, earlier: nil, discarded: nil)
    }
    let tree = GitFileTreeNode.build(files)
    precondition(tree.count == 3 && tree[0].path == "app/UI" && tree[0].name == "app / UI")
    precondition(tree[0].children.map(\.name) == ["Changes.swift", "Composer.swift"])
    precondition(tree[1].name == "web" && tree[2].name == "README.md")
    precondition(files[0].symbol == "swift" && files[3].symbol == "curlybraces")
    print("Git matching, aligned split diffs, and compact file tree checks passed")
  }
}
