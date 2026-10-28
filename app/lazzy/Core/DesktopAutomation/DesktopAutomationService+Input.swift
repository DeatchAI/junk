import AppKit
import CoreGraphics

extension DesktopAutomationService {
  func post(_ event: CGEvent, pid: pid_t, foreground: Bool) {
    if foreground { event.post(tap: .cgSessionEventTap) }
    else { event.postToPid(pid) }
  }

  func sendClick(_ point: CGPoint, pid: pid_t, foreground: Bool, button: String, count: Int) throws {
    let right = button == "right"
    let source = CGEventSource(stateID: .privateState)
    for n in 1...count {
      guard let down = CGEvent(mouseEventSource: source, mouseType: right ? .rightMouseDown : .leftMouseDown,
        mouseCursorPosition: point, mouseButton: right ? .right : .left),
        let up = CGEvent(mouseEventSource: source, mouseType: right ? .rightMouseUp : .leftMouseUp,
          mouseCursorPosition: point, mouseButton: right ? .right : .left) else { throw DesktopAutomationError("Could not create click.") }
      down.setIntegerValueField(.mouseEventClickState, value: Int64(n))
      up.setIntegerValueField(.mouseEventClickState, value: Int64(n))
      post(down, pid: pid, foreground: foreground); post(up, pid: pid, foreground: foreground)
    }
  }

  func sendKey(_ code: CGKeyCode, flags: CGEventFlags, pid: pid_t, foreground: Bool, count: Int) throws {
    let source = CGEventSource(stateID: .privateState)
    for _ in 0..<count {
      guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { throw DesktopAutomationError("Could not create key event.") }
      down.flags = flags; up.flags = flags
      post(down, pid: pid, foreground: foreground); post(up, pid: pid, foreground: foreground)
    }
  }

  func sendDrag(_ start: CGPoint, end: CGPoint, pid: pid_t, foreground: Bool,
    session: DesktopSession, payload: [String: Any]) async throws {
    let source = CGEventSource(stateID: .privateState)
    guard let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left),
      let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left) else {
      throw DesktopAutomationError("Could not create drag events.")
    }
    var last = start
    post(down, pid: pid, foreground: foreground)
    defer { up.location = last; post(up, pid: pid, foreground: foreground) }
    for step in 1...16 {
      try checkSession(session, payload)
      if let observation = session.observation { try yieldToHuman(observation, global: foreground) }
      let fraction = CGFloat(step) / 16
      last = CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
      guard let event = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged,
        mouseCursorPosition: last, mouseButton: .left) else { throw DesktopAutomationError("Could not create drag.") }
      post(event, pid: pid, foreground: foreground)
      try await Task.sleep(for: .milliseconds(16))
    }
  }

  func eventFlags(_ modifiers: [String]) -> CGEventFlags {
    modifiers.reduce(into: CGEventFlags()) { flags, modifier in
      switch modifier.lowercased() {
      case "command": flags.insert(.maskCommand)
      case "option": flags.insert(.maskAlternate)
      case "control": flags.insert(.maskControl)
      case "shift": flags.insert(.maskShift)
      case "fn": flags.insert(.maskSecondaryFn)
      default: break
      }
    }
  }

  func keyCode(for key: String) -> CGKeyCode? {
    let codes: [String: CGKeyCode] = [
      "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8,
      "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
      "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25,
      "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33,
      "i": 34, "p": 35, "return": 36, "enter": 36, "l": 37, "j": 38, "'": 39,
      "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
      "tab": 48, "space": 49, "`": 50, "delete": 51, "backspace": 51, "escape": 53,
      "esc": 53, "forward_delete": 117, "home": 115, "end": 119, "page_up": 116,
      "page_down": 121, "arrow_left": 123, "left": 123, "arrow_right": 124, "right": 124,
      "arrow_down": 125, "down": 125, "arrow_up": 126, "up": 126,
    ]
    return codes[key]
  }

  func isPrintableKey(_ key: String) -> Bool {
    key.count == 1 || key == "space"
  }

  func string(_ value: Any?) -> String? {
    value as? String
  }

  func bool(_ value: Any?) -> Bool? {
    if let value = value as? Bool { return value }
    return (value as? NSNumber)?.boolValue
  }

  func int(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    return (value as? NSNumber)?.intValue
  }

  func uint32(_ value: Any?) -> UInt32? {
    guard let value = int(value), value >= 0, value <= Int(UInt32.max) else { return nil }
    return UInt32(value)
  }

  func double(_ value: Any?) -> Double? {
    if let value = value as? Double { return value }
    return (value as? NSNumber)?.doubleValue
  }

  func clampedInt(_ value: Any?, defaultValue: Int, range: ClosedRange<Int>) -> Int {
    min(max(int(value) ?? defaultValue, range.lowerBound), range.upperBound)
  }

  func clampedInt32(_ value: Double) -> Int32 {
    Int32(min(max(value.rounded(), Double(Int32.min)), Double(Int32.max)))
  }
}
