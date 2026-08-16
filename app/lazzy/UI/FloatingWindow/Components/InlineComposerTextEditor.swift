import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

struct InlineComposerTextEditor: NSViewRepresentable {
  @Binding var text: String
  @Binding var measuredHeight: CGFloat
  var isFocused: FocusState<Bool>.Binding
  let textColor: NSColor
  let tokenColor: NSColor
  let font: NSFont
  let onSubmit: () -> Void
  let onPasteAttachment: () -> Bool
  let onBackspaceWhenEmpty: () -> Void
  let onFileDrop: ([URL]) -> Void
  let onImageDrop: (NSImage) -> Void
  let onRemoteURLDrop: (URL) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(
      text: $text,
      measuredHeight: $measuredHeight,
      isFocused: isFocused,
      onSubmit: onSubmit,
      onPasteAttachment: onPasteAttachment,
      onBackspaceWhenEmpty: onBackspaceWhenEmpty,
      onFileDrop: onFileDrop,
      onImageDrop: onImageDrop,
      onRemoteURLDrop: onRemoteURLDrop
    )
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = ComposerScrollView()
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = false
    scrollView.hasHorizontalScroller = false
    scrollView.borderType = .noBorder

    let textView = ComposerNSTextView()
    textView.delegate = context.coordinator
    textView.onSubmit = {
      context.coordinator.onSubmit()
    }
    textView.onPasteAttachment = {
      context.coordinator.onPasteAttachment()
    }
    textView.onBackspaceWhenEmpty = {
      context.coordinator.onBackspaceWhenEmpty()
    }
    textView.onFileDrop = {
      context.coordinator.onFileDrop($0)
    }
    textView.onImageDrop = {
      context.coordinator.onImageDrop($0)
    }
    textView.onRemoteURLDrop = {
      context.coordinator.onRemoteURLDrop($0)
    }
    textView.registerForDraggedTypes([
      .fileURL,
      .URL,
      NSPasteboard.PasteboardType(UTType.image.identifier),
      NSPasteboard.PasteboardType(UTType.movie.identifier),
    ])
    textView.isRichText = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.drawsBackground = false
    textView.backgroundColor = .clear
    textView.textContainerInset = NSSize(width: 0, height: 0)
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
    textView.minSize = NSSize(width: 0, height: 24)
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.font = font
    textView.textColor = textColor
    textView.insertionPointColor = textColor
    textView.tokenColor = tokenColor
    textView.baseTextColor = textColor
    textView.baseFont = font

    scrollView.documentView = textView
    scrollView.onLayout = { [weak coordinator = context.coordinator] in
      coordinator?.updateMeasuredHeight()
    }
    context.coordinator.textView = textView
    context.coordinator.scrollView = scrollView
    context.coordinator.updateMeasuredHeight()
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let textView = context.coordinator.textView else { return }
    context.coordinator.text = $text
    context.coordinator.measuredHeight = $measuredHeight
    context.coordinator.isFocused = isFocused
    context.coordinator.onSubmit = onSubmit
    context.coordinator.onPasteAttachment = onPasteAttachment
    context.coordinator.onBackspaceWhenEmpty = onBackspaceWhenEmpty
    context.coordinator.onFileDrop = onFileDrop
    context.coordinator.onImageDrop = onImageDrop
    context.coordinator.onRemoteURLDrop = onRemoteURLDrop

    if textView.string != text {
      textView.string = text
      if textView.window?.firstResponder === textView {
        textView.setSelectedRange(
          NSRange(location: textView.string.utf16.count, length: 0)
        )
      }
    }
    textView.font = font
    textView.textColor = textColor
    textView.insertionPointColor = textColor
    textView.tokenColor = tokenColor
    textView.baseTextColor = textColor
    textView.baseFont = font
    textView.applyInlineTokenStyles()
    context.coordinator.updateMeasuredHeight()

    if isFocused.wrappedValue, textView.window?.firstResponder !== textView {
      DispatchQueue.main.async {
        textView.window?.makeFirstResponder(textView)
      }
    }
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    private let minimumHeight: CGFloat = 24
    private let maximumHeight: CGFloat = 176
    var text: Binding<String>
    var measuredHeight: Binding<CGFloat>
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void
    var onPasteAttachment: () -> Bool
    var onBackspaceWhenEmpty: () -> Void
    var onFileDrop: ([URL]) -> Void
    var onImageDrop: (NSImage) -> Void
    var onRemoteURLDrop: (URL) -> Void
    weak var textView: ComposerNSTextView?
    weak var scrollView: NSScrollView?

    init(
      text: Binding<String>,
      measuredHeight: Binding<CGFloat>,
      isFocused: FocusState<Bool>.Binding,
      onSubmit: @escaping () -> Void,
      onPasteAttachment: @escaping () -> Bool,
      onBackspaceWhenEmpty: @escaping () -> Void,
      onFileDrop: @escaping ([URL]) -> Void,
      onImageDrop: @escaping (NSImage) -> Void,
      onRemoteURLDrop: @escaping (URL) -> Void
    ) {
      self.text = text
      self.measuredHeight = measuredHeight
      self.isFocused = isFocused
      self.onSubmit = onSubmit
      self.onPasteAttachment = onPasteAttachment
      self.onBackspaceWhenEmpty = onBackspaceWhenEmpty
      self.onFileDrop = onFileDrop
      self.onImageDrop = onImageDrop
      self.onRemoteURLDrop = onRemoteURLDrop
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? ComposerNSTextView else { return }
      text.wrappedValue = textView.string
      textView.applyInlineTokenStyles()
      updateMeasuredHeight()
      textView.scrollRangeToVisible(textView.selectedRange())
    }

    func textDidBeginEditing(_ notification: Notification) {
      isFocused.wrappedValue = true
    }

    func updateMeasuredHeight() {
      guard let textView, let scrollView else { return }
      let availableWidth = scrollView.contentSize.width
      guard availableWidth > 0 else { return }

      if abs(textView.frame.width - availableWidth) > 0.5 {
        textView.setFrameSize(NSSize(width: availableWidth, height: textView.frame.height))
      }
      textView.textContainer?.containerSize = NSSize(
        width: availableWidth,
        height: CGFloat.greatestFiniteMagnitude
      )
      textView.layoutManager?.ensureLayout(for: textView.textContainer!)

      let usedHeight = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 0
      let contentHeight = ceil(usedHeight + (textView.textContainerInset.height * 2))
      let viewportHeight = min(max(contentHeight, minimumHeight), maximumHeight)

      if abs(textView.frame.height - max(contentHeight, minimumHeight)) > 0.5 {
        textView.setFrameSize(
          NSSize(width: availableWidth, height: max(contentHeight, minimumHeight))
        )
      }
      guard abs(measuredHeight.wrappedValue - viewportHeight) > 0.5 else { return }
      DispatchQueue.main.async { [weak self] in
        guard let self, abs(self.measuredHeight.wrappedValue - viewportHeight) > 0.5 else {
          return
        }
        self.measuredHeight.wrappedValue = viewportHeight
        self.textView?.scrollRangeToVisible(self.textView?.selectedRange() ?? NSRange())
      }
    }
  }
}

private final class ComposerScrollView: NSScrollView {
  var onLayout: (() -> Void)?

  override func layout() {
    super.layout()
    onLayout?()
  }
}

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
    super.paste(sender)
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
    storage.setAttributes([
      .foregroundColor: baseTextColor,
      .font: baseFont,
    ], range: fullRange)

    let pattern = #"(^|\s)((?:[@/][^\s]+)|(?:(?:https?|file)://[^\s<>()]+)|(?:(?:(?:[A-Za-z0-9._-]+/)*[A-Za-z0-9_-]+\.(?:swift|m|mm|h|ts|tsx|js|jsx|json|md|py|go|rs|java|kt|css|html|yaml|yml|sh|rb|sql|c|cpp|cc|hpp))(?:\s*\(line\s+\d+\)|:\d+)?))"#
    if let regex = try? NSRegularExpression(pattern: pattern) {
      regex.enumerateMatches(in: storage.string, range: fullRange) { match, _, _ in
        guard let tokenRange = match?.range(at: 2), tokenRange.location != NSNotFound else { return }
        storage.addAttributes([
          .foregroundColor: tokenColor,
          .font: baseFont,
          .backgroundColor: tokenColor.withAlphaComponent(0.14),
          .underlineStyle: NSUnderlineStyle.single.rawValue,
          .underlineColor: tokenColor.withAlphaComponent(0.55),
        ], range: tokenRange)
      }
    }

    storage.endEditing()
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
