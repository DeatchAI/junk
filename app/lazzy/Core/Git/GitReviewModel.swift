import Combine
import Foundation

@MainActor final class GitReviewModel: ObservableObject {
  let workspace: String
  let endpoint: RuntimeEndpoint
  @Published var runID: String?
  @Published var conversationID: String?
  @Published var sessionScope = false
  @Published var projectScope = false
  @Published var selectedPath: String?
  @Published private(set) var review: GitReviewResponse?
  @Published private(set) var isLoading = false
  @Published private(set) var isMutating = false
  @Published private(set) var error: String?
  @Published private(set) var notice: String?
  @Published var preview: GitRestorePreview?
  private var loadID = UUID()

  init(workspace: String, runID: String?, path: String? = nil, initial: GitReviewResponse? = nil,
       conversationID: String? = nil, endpoint: RuntimeEndpoint? = nil) {
    self.workspace = workspace; self.runID = runID; selectedPath = path; review = initial
    self.endpoint = endpoint ?? .local
    self.conversationID = conversationID; sessionScope = conversationID != nil
    projectScope = runID == nil
    selectAvailableFile()
  }

  var selectedFile: GitFileChange? { review?.files.first { $0.path == selectedPath } }
  var canDiscardTask: Bool {
    !projectScope && !sessionScope && review?.canDiscard == true && review?.files.contains { $0.discarded != true } == true && !isMutating
  }

  func refresh() async {
    let id = UUID(); loadID = id; isLoading = true; error = nil
    defer { if loadID == id { isLoading = false } }
    do {
      let value = try await GitReviewAPI.review(workspace: workspace, runID: runID, project: projectScope,
        conversationID: sessionScope ? conversationID : nil, endpoint: endpoint)
      guard loadID == id, !Task.isCancelled else { return }
      review = value; selectAvailableFile()
    } catch { if loadID == id, !Task.isCancelled { self.error = error.localizedDescription } }
  }

  func prepare(paths: [String]? = nil, undo: Bool = false) async {
    guard !isMutating, runID != nil || (sessionScope && conversationID != nil) else { return }
    isMutating = true; error = nil
    defer { isMutating = false }
    do {
      var body: [String: Any] = ["workspace": workspace, "undo": undo]
      if sessionScope, let conversationID { body["conversation"] = conversationID }
      else if let runID { body["run"] = runID }
      if let paths { body["paths"] = paths }
      preview = try await GitReviewAPI.request("preview", body: body, endpoint: endpoint)
    } catch { self.error = error.localizedDescription }
  }

  func confirm() async {
    guard let plan = preview, !isMutating else { return }
    preview = nil; isMutating = true; error = nil
    defer { isMutating = false }
    do {
      let result: GitApplyResult = try await GitReviewAPI.request("apply", body: ["plan": plan.id], endpoint: endpoint)
      notice = result.notice
      await refresh()
      if !result.failures.isEmpty { error = result.failures.joined(separator: "\n") }
      NotificationCenter.default.post(name: .gitReviewChanged, object: workspace)
    } catch { self.error = error.localizedDescription }
  }

  private func selectAvailableFile() {
    if review?.files.contains(where: { $0.path == selectedPath }) != true { selectedPath = review?.files.first?.path }
  }
}
