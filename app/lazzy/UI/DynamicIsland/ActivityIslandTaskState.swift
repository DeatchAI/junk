import Combine
import Foundation

/// Presentation state only. Replies still use the original question/permission owners.
@MainActor
final class ActivityIslandTaskState: ObservableObject {
  @Published private(set) var expandedRunID: String?
  @Published private(set) var expandedInteractionHeight: CGFloat?
  @Published private(set) var submittingApprovals: Set<String> = []

  enum Section: Int, CaseIterable {
    case attention, running, recent

    var title: String {
      switch self {
      case .attention: return "Needs your attention"
      case .running: return "Running"
      case .recent: return "Recent"
      }
    }
  }

  static func section(for run: DetachedAgentRun) -> Section {
    if run.needsAttention || run.state == .failed { return .attention }
    return run.isActive ? .running : .recent
  }

  static func ordered(_ runs: [DetachedAgentRun]) -> [DetachedAgentRun] {
    // Preserve the store's ordering within each section, including simultaneous interrupts.
    Section.allCases.flatMap { section in runs.filter { self.section(for: $0) == section } }
  }

  func toggle(_ run: DetachedAgentRun) {
    guard run.needsAttention else { return }
    expandedInteractionHeight = nil
    expandedRunID = expandedRunID == run.id ? nil : run.id
  }

  func select(_ run: DetachedAgentRun) {
    guard run.needsAttention else { return }
    if expandedRunID != run.id { expandedInteractionHeight = nil }
    expandedRunID = run.id
  }

  func collapse() {
    expandedInteractionHeight = nil
    expandedRunID = nil
  }

  func reportHeight(_ height: CGFloat, for runID: String) {
    guard expandedRunID == runID, height.isFinite, height > 0 else { return }
    let height = ceil(height)
    guard expandedInteractionHeight.map({ abs($0 - height) > 0.5 }) ?? true else { return }
    expandedInteractionHeight = height
  }

  func reconcile(_ runs: [DetachedAgentRun]) {
    if let id = expandedRunID, !runs.contains(where: { $0.id == id && $0.needsAttention }) {
      collapse()
    }
    let pending = Set(runs.compactMap { $0.approval?.id })
    let remaining = submittingApprovals.intersection(pending)
    if remaining != submittingApprovals { submittingApprovals = remaining }
  }

  func respond(to approval: DetachedRunApproval, approved: Bool, send: (String, Bool) -> Void) {
    guard submittingApprovals.insert(approval.id).inserted else { return }
    send(approval.id, approved)
  }
}
