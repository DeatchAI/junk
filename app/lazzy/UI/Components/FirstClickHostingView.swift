import AppKit
import SwiftUI

/// Controls in a nonactivating panel must respond even when another app is key.
/// Leave NSHostingView's background dragging intact for movable composers.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
