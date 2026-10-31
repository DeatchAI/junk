import CoreGraphics

enum ActivityIslandContentLayout {
  static let rowHeight: CGFloat = 62
  static let expandedRowHeight: CGFloat = 48
  static let contentTopInset: CGFloat = 8
  static let sideInset: CGFloat = 16
  static let topInset: CGFloat = 32
  static let bottomInset: CGFloat = 8
  static let headerHeight: CGFloat = 30
  static let sectionHeight: CGFloat = 26
  static let questionHeight: CGFloat = 228
  static let approvalHeight: CGFloat = 132
  static let credentialHeight: CGFloat = 80

  static func size(taskCount: Int, hasQuestion: Bool, hasApproval: Bool, hasCredential: Bool,
    sectionCount: Int = 1, interactionHeight: CGFloat? = nil) -> CGSize {
    let fallback: CGFloat = hasQuestion ? questionHeight : hasApproval ? approvalHeight : hasCredential ? credentialHeight : 0
    let interrupt = fallback > 0 ? min(max(interactionHeight ?? fallback, 0), fallback) : 0
    let rows = min(max(taskCount, 1), interrupt > 0 ? 3 : 6)
    let headerReduction = interrupt > 0 ? rowHeight - expandedRowHeight : 0
    let height = contentTopInset + headerHeight + CGFloat(max(sectionCount, 1)) * sectionHeight
      + interrupt + CGFloat(rows) * rowHeight + bottomInset - headerReduction
    return CGSize(width: 500, height: min(height, 560))
  }
}
