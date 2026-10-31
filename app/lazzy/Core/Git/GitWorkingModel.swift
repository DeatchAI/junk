import Combine
import Foundation

struct GitWorkingStatus: Decodable {
  let repository: GitRepositoryInfo?
  let head: String
  let remotes: [String]
  let upstream: String?
  let ahead: Int
  let behind: Int
  let remote: String?
  let remoteBranch: String?
  let canCommit: Bool
  let canPush: Bool
  let pushReason: String?
  let busy: Bool
}

struct GitSessionSafety: Decodable {
  let repository: GitRepositoryInfo?
  let hasChanges: Bool
  let canRevert: Bool
  let canUndo: Bool
  let reason: String?
  let recoveryID: String?
  let runID: String?
}

@MainActor final class GitWorkingModel: ObservableObject {
  var endpoint: RuntimeEndpoint = .local
  @Published private(set) var status: GitWorkingStatus?
  @Published private(set) var isBusy = false
  @Published private(set) var error: String?
  @Published private(set) var notice: String?

  func clearFeedback() { error = nil; notice = nil }

  func refresh(workspace: String) async {
    do { status = try await GitReviewAPI.request("working-status", query: ["workspace": workspace], endpoint: endpoint) }
    catch { self.error = error.localizedDescription }
  }

  func commit(workspace: String, scope: String, id: String?, paths: [String], message: String) async -> Bool {
    guard let branch = status?.repository?.branch, !isBusy else { return false }
    isBusy = true; error = nil; notice = nil
    defer { isBusy = false }
    do {
      var body: [String: Any] = ["workspace": workspace, "scope": scope, "paths": paths, "branch": branch]
      if let id { body["id"] = id }
      let plan: CommitPreview = try await GitReviewAPI.request("commit-preview", body: body, endpoint: endpoint)
      let result: Result = try await GitReviewAPI.request("commit", body: ["plan": plan.id, "message": message], endpoint: endpoint)
      notice = result.notice
      await refresh(workspace: workspace)
      NotificationCenter.default.post(name: .gitReviewChanged, object: workspace)
      return true
    } catch { self.error = error.localizedDescription; return false }
  }

  func push(workspace: String, remote: String) async -> Bool {
    guard let status, let branch = status.repository?.branch, let destination = status.remoteBranch, !isBusy else { return false }
    isBusy = true; error = nil; notice = nil
    defer { isBusy = false }
    do {
      let result: Result = try await GitReviewAPI.request("push", body: ["workspace": workspace, "head": status.head,
        "branch": branch, "remote": remote, "remoteBranch": destination], endpoint: endpoint)
      notice = result.notice
      await refresh(workspace: workspace)
      NotificationCenter.default.post(name: .gitReviewChanged, object: workspace)
      return true
    } catch { self.error = error.localizedDescription; return false }
  }

  private struct CommitPreview: Decodable { let id: String }
  private struct Result: Decodable { let notice: String }
}
