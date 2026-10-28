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
  var tokens: [ComposerInlineToken] = []
  var documentID: UUID? = nil
  var menuAnchorOffset: Int? = nil
  var onCaretRectChange: (NSRect) -> Void = { _ in }
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
    textView.isRichText = true
    textView.importsGraphics = false
    textView.usesFontPanel = false
    textView.allowsUndo = true
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
    context.coordinator.onCaretRectChange = onCaretRectChange
    context.coordinator.menuAnchorOffset = menuAnchorOffset

    let documentChanged = textView.documentID != documentID
    if documentChanged {
      textView.documentID = documentID
      textView.knownTokens = [:]
      textView.undoManager?.removeAllActions()
    }
    textView.updateInlineText(text, tokens: tokens, font: font, color: textColor)
    textView.font = font
    textView.textColor = textColor
    textView.insertionPointColor = textColor
    textView.tokenColor = tokenColor
    textView.baseTextColor = textColor
    textView.baseFont = font
    textView.applyInlineTokenStyles()
    context.coordinator.updateMeasuredHeight()
    if documentChanged {
      textView.setSelectedRange(NSRange(location: 0, length: 0))
      DispatchQueue.main.async {
        guard textView.documentID == documentID else { return }
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
      }
    }

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
    var onCaretRectChange: (NSRect) -> Void = { _ in }
    var menuAnchorOffset: Int?
    private var lastCaretRect: NSRect?
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
      text.wrappedValue = ComposerTokenText.serialized(textView.attributedString())
      textView.applyInlineTokenStyles()
      updateMeasuredHeight()
      textView.scrollRangeToVisible(textView.selectedRange())
    }

    func textDidBeginEditing(_ notification: Notification) {
      isFocused.wrappedValue = true
    }

    func textViewDidChangeSelection(_ notification: Notification) {
      updateCaretPosition()
    }

    private func updateCaretPosition() {
      guard let textView, let window = textView.window else { return }
      let attributed = textView.attributedString()
      let offset = menuAnchorOffset.map { ComposerTokenText.displayOffset($0, in: attributed) }
        ?? textView.selectedRange().location
      let screenRect = textView.firstRect(forCharacterRange: NSRange(location: min(offset, attributed.length), length: 0),
        actualRange: nil)
      guard !screenRect.isEmpty else { return }
      let rect = window.convertFromScreen(screenRect)
      guard rect != lastCaretRect else { return }
      lastCaretRect = rect
      DispatchQueue.main.async { [weak self] in self?.onCaretRectChange(rect) }
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
      updateCaretPosition()

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
