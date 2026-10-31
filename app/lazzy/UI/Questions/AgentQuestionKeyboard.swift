import AppKit
import SwiftUI

enum AgentQuestionKeyboardAction: Equatable {
  case select(Int)
  case continueAnswer

  static func resolve(characters: String?, keyCode: UInt16, modifiers: NSEvent.ModifierFlags,
    optionCount: Int, canContinue: Bool, isEditingText: Bool) -> Self? {
    guard !isEditingText, modifiers.intersection([.command, .option, .control, .shift]).isEmpty else { return nil }
    if let characters, characters.count == 1, let number = Int(characters),
      (1...9).contains(number), number <= optionCount { return .select(number - 1) }
    return canContinue && (keyCode == 36 || keyCode == 76) ? .continueAnswer : nil
  }
}

/// A local monitor scoped to this visible form's key window; never a global shortcut.
struct AgentQuestionKeyboard: NSViewRepresentable {
  let enabled: Bool
  let optionCount: Int
  let canContinue: Bool
  let isActive: () -> Bool
  let onSelect: (Int) -> Void
  let onContinue: () -> Void

  func makeNSView(context: Context) -> KeyView { KeyView() }

  func updateNSView(_ view: KeyView, context: Context) {
    view.handleKey = { event, editing in
      guard enabled, isActive(), let action = AgentQuestionKeyboardAction.resolve(
        characters: event.charactersIgnoringModifiers, keyCode: event.keyCode,
        modifiers: event.modifierFlags, optionCount: optionCount, canContinue: canContinue, isEditingText: editing)
      else { return false }
      if !event.isARepeat {
        switch action {
        case .select(let index): onSelect(index)
        case .continueAnswer: onContinue()
        }
      }
      return true
    }
  }

  static func dismantleNSView(_ view: KeyView, coordinator: ()) {
    view.removeMonitor()
    view.handleKey = nil
  }

  final class KeyView: NSView {
    var handleKey: ((NSEvent, Bool) -> Bool)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      removeMonitor()
      guard window != nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self, let window = self.window, window.isKeyWindow,
          event.window === window, !self.isHiddenOrHasHiddenAncestor, !self.visibleRect.isEmpty
        else { return event }
        let responder = window.firstResponder
        let editing = (responder as? NSTextView)?.isEditable == true || responder is NSTextField
        return self.handleKey?(event, editing) == true ? nil : event
      }
    }

    func removeMonitor() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
  }
}
