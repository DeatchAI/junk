import Foundation

enum ActivityIslandPlacement: String, CaseIterable, Identifiable {
  case left
  case right
  case top

  static let defaultPlacement: Self = .right

  var id: String { rawValue }
  var isSide: Bool { self != .top }

  var title: String {
    switch self {
    case .left: return "Left"
    case .right: return "Right"
    case .top: return "Top"
    }
  }
}
