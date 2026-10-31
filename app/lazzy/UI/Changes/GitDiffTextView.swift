import AppKit
import SwiftUI

struct GitDiffTextView: NSViewRepresentable {
  let text: String
  let foreground: NSColor
  let background: NSColor

  var split = true

  func makeNSView(context: Context) -> GitDiffEditor { GitDiffEditor() }
  func updateNSView(_ view: GitDiffEditor, context: Context) {
    view.update(text: text, foreground: foreground, background: background, split: split)
  }
}
