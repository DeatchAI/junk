import AppKit
import SwiftUI

@main
struct DropdownInteractionTests {
  @MainActor static func main() {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let anchor = CGRect(x: 300, y: 450, width: 100, height: 30)
    let menuSize = CGSize(width: 200, height: 240)
    for placement in [DropdownPanelPlacement.below, .trailing] {
      let menu = DropdownPanelLayout.frame(anchor: anchor, size: menuSize,
                                           visibleFrame: screen, placement: placement)
      assert(!menu.intersects(anchor), "Menus must not intercept their trigger's clicks")
      assert(screen.contains(menu))
      let bridge = DropdownPanelLayout.hoverBridge(anchor: anchor, panel: menu)
      assert(bridge.width > 0 && bridge.height > 0, "The pointer must be able to cross into the menu")
      assert(!bridge.contains(CGPoint(x: anchor.maxX + 30, y: anchor.midY)),
             "The menu bridge must not include adjacent toolbar buttons")
    }
    let bottomAnchor = CGRect(x: 300, y: 10, width: 100, height: 30)
    let flipped = DropdownPanelLayout.frame(anchor: bottomAnchor, size: menuSize,
                                            visibleFrame: screen, placement: .below)
    assert(flipped.minY > bottomAnchor.maxY, "Flip above instead of covering the trigger")
    let rightAnchor = CGRect(x: 1390, y: 400, width: 40, height: 30)
    let leftMenu = DropdownPanelLayout.frame(anchor: rightAnchor, size: menuSize,
                                             visibleFrame: screen, placement: .trailing)
    assert(leftMenu.maxX < rightAnchor.minX, "Nested menus must flip at the display edge")

    let host = FirstClickHostingView(rootView: Button("History") {})
    assert(host.acceptsFirstMouse(for: nil), "An inactive composer must accept the first click")
    let backgroundHost = FirstClickHostingView(rootView: Color.clear.frame(width: 500, height: 120))
    assert(backgroundHost.mouseDownCanMoveWindow,
           "The hosting view must allow dragging empty composer space")
    let parent = NSWindow(contentRect: CGRect(x: 300, y: 500, width: 500, height: 120),
                          styleMask: .borderless, backing: .buffered, defer: false)
    parent.contentView = NSView(frame: CGRect(x: 0, y: 0, width: 500, height: 120))
    let trigger = NSView(frame: CGRect(x: 20, y: 40, width: 100, height: 30))
    parent.contentView!.addSubview(trigger)
    let first = Presentation(), second = Presentation()
    let menu = Text("Provider options").frame(width: 200, height: 240)
    let firstAnchor = DropdownPanelAnchor(isPresented: first.binding, menuWidth: 200, menu: menu)
    let firstCoordinator = firstAnchor.makeCoordinator()
    firstCoordinator.present(menu: menu, menuWidth: 200, placement: .below,
                             opensOnHover: true, contentRevision: 1, from: trigger)
    let popup = parent.childWindows!.first!
    assert(!popup.canBecomeKey, "Ordinary agent/model menus must preserve editor focus")
    assert(popup.frame.width == 200, "Transparent window margins must not cover the toolbar")
    let originalHost = popup.contentView!
    firstCoordinator.present(menu: menu, menuWidth: 200, placement: .below,
                             opensOnHover: true, contentRevision: 1, from: trigger)
    assert(popup.contentView === originalHost, "Reuse the menu host while moving the pointer")
    let secondAnchor = DropdownPanelAnchor(isPresented: second.binding, menuWidth: 200, menu: menu)
    let secondCoordinator = secondAnchor.makeCoordinator()
    secondCoordinator.present(menu: menu, menuWidth: 200, placement: .below,
                              opensOnHover: true, contentRevision: 2, from: trigger)
    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    assert(!popup.isVisible && !first.presented, "Opening a sibling must close the previous menu")
    assert(parent.childWindows?.count == 1)
    secondCoordinator.dismiss()
    let searchPresentation = Presentation()
    let searchMenu = TextField("Search projects", text: .constant("")).frame(width: 300, height: 240)
    let searchAnchor = DropdownPanelAnchor(isPresented: searchPresentation.binding, menuWidth: 300,
      menu: searchMenu, acceptsKeyboardInput: true)
    let searchCoordinator = searchAnchor.makeCoordinator()
    searchCoordinator.present(menu: searchMenu, menuWidth: 300, placement: .below,
      opensOnHover: false, contentRevision: 1, acceptsKeyboardInput: true, from: trigger)
    let searchPopup = parent.childWindows!.first!
    assert(searchPopup.canBecomeKey && !(searchPopup as! NSPanel).becomesKeyOnlyIfNeeded,
      "Custom project search must accept keyboard input")
    searchCoordinator.dismiss()
    parent.orderOut(nil)
    print("Composer checks passed: first click, background dragging, menu hit bounds, hover bridge, screen-edge flipping, host reuse, and sibling dismissal")
  }
}

@MainActor
private final class Presentation {
  var presented = true
  var binding: Binding<Bool> { Binding(get: { self.presented }, set: { self.presented = $0 }) }
}
