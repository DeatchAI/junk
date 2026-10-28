import CoreGraphics

enum ActivityIslandContentLayout {
  static let rowHeight: CGFloat = 74
  static let sideInset: CGFloat = 20
  static let topInset: CGFloat = 32
  static let bottomInset: CGFloat = 8
  static let questionHeight: CGFloat = 350
  static let approvalHeight: CGFloat = 220
  static let credentialHeight: CGFloat = 150

  static func size(taskCount: Int, hasQuestion: Bool, hasApproval: Bool, hasCredential: Bool) -> CGSize {
    let interrupt: CGFloat = hasQuestion ? questionHeight : hasApproval ? approvalHeight : hasCredential ? credentialHeight : 0
    let rows = min(max(taskCount, 1), interrupt > 0 ? 2 : 5)
    return CGSize(width: 560, height: interrupt + CGFloat(rows) * rowHeight + bottomInset)
  }
}
