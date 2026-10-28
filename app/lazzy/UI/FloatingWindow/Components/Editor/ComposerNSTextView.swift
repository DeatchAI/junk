import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

final class ComposerNSTextView: NSTextView {
  var onSubmit: (() -> Void)?
  var onPasteAttachment: (() -> Bool)?
  var onBackspaceWhenEmpty: (() -> Void)?
  var onFileDrop: (([URL]) -> Void)?
  var onImageDrop: ((NSImage) -> Void)?
  var onRemoteURLDrop: ((URL) -> Void)?
  var tokenColor: NSColor = .systemBlue
  var baseTextColor: NSColor = .labelColor
  var baseFont: NSFont = NSFont.systemFont(ofSize: 14)
  var knownTokens: [String: ComposerInlineToken] = [:]
  var documentID: UUID?
  private var renderedTokens: [ComposerInlineToken] = []

  func updateInlineText(_ text: String, tokens: [ComposerInlineToken], font: NSFont, color: NSColor) {
    guard !hasMarkedText(), let storage = textStorage else { return }
    tokens.forEach { knownTokens[$0.id] = $0 }
    let previous = attributedString()
    let externalEdit = ComposerTokenText.serialized(previous) != text
    guard externalEdit || tokens != renderedTokens || font != baseFont || color != baseTextColor else { return }
    let selection = selectedRange()
    let rawStart = ComposerTokenText.rawOffset(selection.location, in: previous)
    let rawEnd = ComposerTokenText.rawOffset(NSMaxRange(selection), in: previous)
    let content = ComposerTokenText.render(text, tokens: Array(knownTokens.values), font: font, color: color,
      maximumWidth: 220)
    storage.setAttributedString(content)
    if externalEdit {
      undoManager?.removeAllActions()
      setSelectedRange(NSRange(location: content.length, length: 0))
    } else {
      let start = ComposerTokenText.displayOffset(rawStart, in: content)
      let end = ComposerTokenText.displayOffset(rawEnd, in: content)
      setSelectedRange(NSRange(location: start, length: max(0, end - start)))
    }
    renderedTokens = tokens
    typingAttributes = [.font: font, .foregroundColor: color]
  }

  override func keyDown(with event: NSEvent) {
    if !hasMarkedText(), event.matches(ShortcutSettings.chatSubmit) {
      onSubmit?()
      return
    }

    if !hasMarkedText(), isAttachmentPasteShortcut(event), onPasteAttachment?() == true {
      return
    }

    if Int(event.keyCode) == 51 {
      if deleteInlineTokenBeforeCursor() {
        return
      }
      if string.isEmpty {
        onBackspaceWhenEmpty?()
        return
      }
    }
    super.keyDown(with: event)
  }

  override func paste(_ sender: Any?) {
    if !hasMarkedText(), onPasteAttachment?() == true {
      return
    }
    if let plain = NSPasteboard.general.string(forType: .string) {
      insertText(plain, replacementRange: selectedRange())
    }
  }

  override func copy(_ sender: Any?) {
    guard selectedRange().length > 0 else { return }
    let selection = attributedString().attributedSubstring(from: selectedRange())
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(ComposerTokenText.serialized(selection, readable: true), forType: .string)
  }

  override func cut(_ sender: Any?) {
    copy(sender)
    insertText("", replacementRange: selectedRange())
  }

  private func isAttachmentPasteShortcut(_ event: NSEvent) -> Bool {
    guard Int(event.keyCode) == Int(kVK_ANSI_V) else { return false }
    let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
    return modifiers == .command || modifiers == .control
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    acceptsMediaDrop(sender) ? .copy : super.draggingEntered(sender)
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    acceptsMediaDrop(sender) ? .copy : super.draggingUpdated(sender)
  }

  override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
    acceptsMediaDrop(sender) ? true : super.prepareForDragOperation(sender)
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let urls = droppedFileURLs(from: sender)
    if !urls.isEmpty {
      onFileDrop?(urls)
      return true
    }

    if let image = sender.draggingPasteboard.readObjects(
      forClasses: [NSImage.self],
      options: nil
    )?.first as? NSImage {
      onImageDrop?(image)
      return true
    }

    if let url = droppedRemoteURL(from: sender) {
      onRemoteURLDrop?(url)
      return true
    }

    return super.performDragOperation(sender)
  }

  private func droppedFileURLs(from sender: NSDraggingInfo) -> [URL] {
    (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? [])
      .filter(\.isFileURL)
  }

  private func droppedRemoteURL(from sender: NSDraggingInfo) -> URL? {
    (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? [])
      .first(where: { !$0.isFileURL && ($0.scheme == "https" || $0.scheme == "http") })
  }

  private func acceptsMediaDrop(_ sender: NSDraggingInfo) -> Bool {
    if !droppedFileURLs(from: sender).isEmpty { return true }
    if sender.draggingPasteboard.canReadObject(forClasses: [NSImage.self]) { return true }
    return droppedRemoteURL(from: sender) != nil
  }

  func applyInlineTokenStyles() {
    guard let storage = textStorage else { return }
    let selectedRanges = self.selectedRanges
    let fullRange = NSRange(location: 0, length: storage.length)
    storage.beginEditing()
    storage.addAttributes([
      .foregroundColor: baseTextColor,
      .font: baseFont,
    ], range: fullRange)

    storage.endEditing()
    typingAttributes = [.font: baseFont, .foregroundColor: baseTextColor]
    self.selectedRanges = selectedRanges
  }

  private func deleteInlineTokenBeforeCursor() -> Bool {
    let range = selectedRange()
    guard range.length == 0, range.location > 0 else { return false }

    let prefix = (string as NSString).substring(to: range.location)
    guard let regex = try? NSRegularExpression(pattern: #"(^|\s)([@/][^\s]+)\s*$"#) else {
      return false
    }
    let fullRange = NSRange(location: 0, length: (prefix as NSString).length)
    guard let match = regex.firstMatch(in: prefix, range: fullRange) else { return false }
    let tokenRange = match.range(at: 2)
    guard tokenRange.location != NSNotFound else { return false }

    var deleteRange = tokenRange
    if tokenRange.location > 0 {
      let previousLocation = tokenRange.location - 1
      let previous = (prefix as NSString).substring(with: NSRange(location: previousLocation, length: 1))
      if previous.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        deleteRange = NSRange(location: previousLocation, length: tokenRange.length + 1)
      }
    }

    textStorage?.deleteCharacters(in: deleteRange)
    setSelectedRange(NSRange(location: deleteRange.location, length: 0))
    didChangeText()
    applyInlineTokenStyles()
    return true
  }
}
