import CoreGraphics
import Foundation
import SwiftUI

@main
struct ActivityIslandLayoutTests {
  static func main() {
    let displays = [
      CGRect(x: 0, y: 0, width: 1512, height: 982),
      CGRect(x: -1920, y: -180, width: 1920, height: 1080),
      CGRect(x: 0, y: 982, width: 1024, height: 768),
    ]
    var checks = 0
    var historyChecks = 0
    for display in displays {
      // Also model a side Dock, menu bar, and nonzero display origin.
      let visible = display.insetBy(dx: 64, dy: 32)
      for placement in ActivityIslandPlacement.allCases {
        for expanded in [false, true] {
          let frame = ActivityIslandLayout.frame(
            placement: placement, screenFrame: display, visibleFrame: visible,
            physicalNotch: CGSize(width: 200, height: 32), expanded: expanded,
            contentSize: CGSize(width: 560, height: 360)
          )
          expect(display.contains(frame), "Panel must stay on its display")
          if placement.isSide {
            expect(visible.contains(frame), "Side panel must avoid the Dock/menu bar")
            expect(frame.midY == visible.midY, "Expansion must keep the vertical anchor")
            expect(
              placement == .left ? frame.minX == visible.minX : frame.maxX == visible.maxX,
              "Expansion must stay attached to the selected edge"
            )
          } else {
            expect(frame.maxY == display.maxY, "Top panel must meet the top edge")
            expect(frame.midX == display.midX, "Top panel must remain centered")
          }
          let shape = ScreenEdgeNotchShape(placement: placement)
          let bounds = CGRect(origin: .zero, size: frame.size)
          let path = shape.path(in: bounds)
          expect(path.boundingRect == bounds, "Rotated shape must fill its panel bounds")
          expect(path.contains(CGPoint(x: bounds.midX, y: bounds.midY)), "Shape must contain its controls")
          checks += 1
        }
      }
    }
    for display in displays {
      let visible = display.insetBy(dx: 64, dy: 32)
      for placement in [ActivityIslandPlacement.left, .right] {
        let expanded = HistoryPanelLayout.frame(placement: placement, visibleFrame: visible, expanded: true)
        let compact = HistoryPanelLayout.frame(placement: placement, visibleFrame: visible, expanded: false)
        expect(visible.contains(expanded), "History must fit the usable display")
        expect(expanded.midY == compact.midY, "History must expand from its edge anchor")
        expect(
          placement == .left ? expanded.minX == compact.minX : expanded.maxX == compact.maxX,
          "History must stay attached while expanding"
        )
        historyChecks += 1
      }
    }
    expect(ActivityIslandPlacement.defaultPlacement == .right, "New placement must avoid the top notch")
    print("Screen edge layouts: \(checks) activity and \(historyChecks) history combinations passed")
  }

  private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
  }
}
