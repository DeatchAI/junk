import AppKit
@testable import Detach

@main struct InlineComposerTokenTests {
  @MainActor static func main() {
    _ = NSApplication.shared
    var count = 0
    func expect(_ value: Bool, _ message: String) {
      precondition(value, message); count += 1
    }
    func file(_ path: String) -> ChatAttachment {
      ChatAttachment(thumbnail: NSImage(), fileRequest: FileAttachmentRequest(path: path, mimeType: "text/plain"),
        fileName: URL(fileURLWithPath: path).lastPathComponent)
    }
    let first = file("/tmp/project/Composer.swift"), second = file("/tmp/other/Composer.swift")
    let tokenA = ComposerInlineToken.file(first), tokenB = ComposerInlineToken.file(second)
    let raw = "Review 👋 \(tokenA.marker) alongside \(tokenB.marker) please."
    let rendered = ComposerTokenText.render(raw, tokens: [tokenA, tokenB], font: .systemFont(ofSize: 14),
      color: .white, maximumWidth: 220)
    expect(rendered.string.filter { $0 == "\u{FFFC}" }.count == 2, "Files occupy atomic inline positions")
    expect(ComposerTokenText.serialized(rendered) == raw, "Rendering preserves exact source positions and Unicode")
    expect(ComposerTokenText.serialized(rendered, readable: true) == "Review 👋 @Composer.swift alongside @Composer.swift please.",
      "Copied text contains readable names, never internal markers")
    expect(tokenA.marker != tokenB.marker, "Files sharing a name retain distinct identities")
    for offset in 0...rendered.length {
      let sourceOffset = ComposerTokenText.rawOffset(offset, in: rendered)
      expect(ComposerTokenText.displayOffset(sourceOffset, in: rendered) == offset,
        "Cursor and selection positions round-trip across inline pills")
    }
    let draft = ComposerDraft(text: raw, attachments: [first, second])
    expect(!draft.resolvedText.contains("[[file:") && draft.files.count == 2,
      "Provider requests receive readable text and real file payloads")
    let context = DetectedContent(type: .text, text: "Captured code", files: nil)
    let contextDraft = ComposerDraft(text: ComposerInlineToken.context(context).marker, contexts: [context])
    expect(contextDraft.resolvedText == "@Selected-text", "Selected text also resolves without editor metadata")
    let withFile = ComposerInlineToken.addingMissingFiles(to: "Revise @Composer.swift next", attachments: [first], contexts: [])
    expect(withFile == "Revise \(tokenA.marker) next", "Revising history restores the pill's original inline position")
    expect(ComposerInlineToken.addingMissingFiles(to: withFile, attachments: [first], contexts: []) == withFile,
      "Attachment synchronization never duplicates existing pills")
    let image = ChatAttachment(thumbnail: NSImage(), fileRequest: FileAttachmentRequest(path: "/tmp/image.png",
      mimeType: "image/png"), fileName: "image.png")
    expect(ComposerInlineToken.addingMissingFiles(to: "Describe this", attachments: [image], contexts: []) == "Describe this",
      "Media remains exclusively in the thumbnail row")
    let browser = ComposerInlineToken.mention(id: "browser", name: "Browser", symbol: "globe")
    let browserText = ComposerTokenText.render("@Browser @Browserish", tokens: [browser], font: .systemFont(ofSize: 14),
      color: .white, maximumWidth: 220)
    expect(browserText.string == "\u{FFFC} @Browserish", "Mentions only replace a complete selected token")

    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
      styleMask: [.titled], backing: .buffered, defer: false)
    let editor = ComposerNSTextView(frame: window.contentView!.bounds)
    editor.allowsUndo = true; editor.baseFont = .systemFont(ofSize: 14)
    window.contentView?.addSubview(editor)
    window.makeFirstResponder(editor)
    editor.updateInlineText(raw, tokens: [tokenA, tokenB], font: editor.baseFont, color: .white)
    let text = editor.attributedString()
    let cursor = (text.string as NSString).range(of: "\u{FFFC}").location + 1
    editor.setSelectedRange(NSRange(location: cursor, length: 0))
    editor.deleteBackward(nil)
    expect(!ComposerTokenText.serialized(editor.attributedString()).contains(tokenA.marker)
      && ComposerTokenText.serialized(editor.attributedString()).contains(tokenB.marker),
      "Backspace removes one complete pill and preserves the other file")
    editor.undoManager?.undo()
    expect(ComposerTokenText.serialized(editor.attributedString()) == raw, "Undo restores the full inline attachment")

    let layout = NSLayoutManager(), container = NSTextContainer(containerSize: NSSize(width: 420, height: CGFloat.greatestFiniteMagnitude))
    let storage = NSTextStorage(attributedString: ComposerTokenText.render(String(repeating: raw + " ", count: 3),
      tokens: [tokenA, tokenB], font: .systemFont(ofSize: 14), color: .white, maximumWidth: 220))
    layout.addTextContainer(container); storage.addLayoutManager(layout); layout.ensureLayout(for: container)
    let bounds = layout.usedRect(for: container)
    expect(bounds.height > 46 && bounds.width <= 420, "Pills wrap with prose inside the native text container")
    print("Passed \(count) inline token, cursor, request, deletion, undo, and wrapping checks.")
  }
}
