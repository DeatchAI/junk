import AppKit
import Combine
import Foundation

#if DEBUG
private final class DebugDemoShortcutRouter {
  weak var workspace: FloatingWindowWorkspaceController?

  private var keyDownMonitor: Any?
  private var functionKeyMonitor: Any?
  private var functionKeyUpMonitor: Any?
  private var mouseMoveMonitor: Any?
  private weak var hoveredWindow: NSWindow?
  private var isFunctionKeyDown = false

  init() {
    functionKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
      [weak self] event in
      guard let self, event.keyCode == 63 else { return event }
      self.isFunctionKeyDown = event.modifierFlags.contains(.function)
        || event.cgEvent?.flags.contains(.maskSecondaryFn) == true
      return event
    }

    functionKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) {
      [weak self] event in
      if event.keyCode == 63 {
        self?.isFunctionKeyDown = false
      }
      return event
    }

    mouseMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) {
      [weak self] event in
      self?.hoveredWindow = event.window
      return event
    }

    keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
      [weak self] event in
      if event.keyCode == 63 {
        self?.isFunctionKeyDown = true
        return event
      }

      guard let self,
        let workspace = self.workspace,
        let task = workspace.tasks.first(where: {
          guard let hoveredWindow = self.hoveredWindow,
            $0.controller.isVisible
          else {
            return false
          }
          return $0.controller.ownsDebugWindow(hoveredWindow)
        }) ?? workspace.tasks.first(where: { $0.controller.containsPointer() }),
        let handler = task.controller.onDebugDemoKeyDown
      else {
        return event
      }

      let functionIsDown = self.isFunctionKeyDown
        || event.modifierFlags.contains(.function)
        || event.cgEvent?.flags.contains(.maskSecondaryFn) == true
      return handler(event, functionIsDown) ? nil : event
    }
  }

  deinit {
    if let keyDownMonitor {
      NSEvent.removeMonitor(keyDownMonitor)
    }
    if let functionKeyMonitor {
      NSEvent.removeMonitor(functionKeyMonitor)
    }
    if let functionKeyUpMonitor {
      NSEvent.removeMonitor(functionKeyUpMonitor)
    }
    if let mouseMoveMonitor {
      NSEvent.removeMonitor(mouseMoveMonitor)
    }
  }
}
#endif

/// Owns the independent composer windows that make up the floating agent
/// workspace. A task is retained after its panel closes so an in-flight agent
/// can continue streaming activity to the notch.
final class FloatingWindowWorkspaceController: ObservableObject {
  final class Task: Identifiable {
    let id = UUID()
    let controller: FloatingWindowController
    let wsManager: WebSocketManager
    let openedAt = Date()

    init(controller: FloatingWindowController, wsManager: WebSocketManager) {
      self.controller = controller
      self.wsManager = wsManager
    }
  }

  @Published private(set) var tasks: [Task] = []
  private var lastActiveTaskID: Task.ID?
#if DEBUG
  private let debugDemoShortcutRouter: DebugDemoShortcutRouter
#endif

  var configureTask: ((Task) -> Void)?
  var onTaskCreated: ((Task) -> Void)?

  init() {
#if DEBUG
    let router = DebugDemoShortcutRouter()
    debugDemoShortcutRouter = router
    router.workspace = self
#endif
  }

  @discardableResult
  func openNewTask(
    at location: NSPoint,
    with content: DetectedContent? = nil,
    conversationId: String? = nil
  ) -> Task {
    let wsManager = WebSocketManager()
    // Set the identity before connecting or constructing the chat view. This
    // lets both the WebSocket connection and the UI agree that this is a
    // conversation reopen, never a blank task.
    if let conversationId {
      wsManager.loadConversation(id: conversationId)
    }
    let controller = FloatingWindowController(wsManager: wsManager)
    let task = Task(controller: controller, wsManager: wsManager)

    controller.onVisibilityChanged = { [weak self, weak task] in
      guard let self, let task else { return }
      if controller.isVisible {
        self.markTaskActive(task)
      }
    }
    controller.onFrontmostStateChanged = { [weak self, weak task] in
      guard let self, let task else { return }
      if controller.isFrontmost {
        self.markTaskActive(task)
      }
    }

    configureTask?(task)
    tasks.append(task)
    onTaskCreated?(task)
    wsManager.connect()

    // A small repeating offset makes a burst of shortcut presses read as a
    // stack of distinct tasks instead of apparently opening the same panel.
    let stackIndex = (tasks.count - 1) % 5
    let offset = CGFloat(stackIndex) * 26
    controller.show(
      at: NSPoint(x: location.x + offset, y: location.y - offset),
      with: content
    )
    markTaskActive(task)
    return task
  }

  @discardableResult
  func openConversation(_ conversationId: String, at location: NSPoint) -> Task {
    openNewTask(at: location, conversationId: conversationId)
  }

  /// Prefer the task that already owns this stream. Its SwiftUI state contains
  /// in-flight response text and activity that a history reload cannot yet see.
  @discardableResult
  func showExistingTask(for conversationId: String, at location: NSPoint) -> Bool {
    guard let task = tasks.last(where: { $0.wsManager.currentConversationId == conversationId }) else {
      return false
    }
    task.controller.bringToFront()
    markTaskActive(task)
    return true
  }

  /// Restores the exact task the user last interacted with, whether it is
  /// currently hidden in the notch or simply behind another application.
  @discardableResult
  func showLastActiveTask(at location: NSPoint) -> Bool {
    let task = lastActiveTaskID.flatMap { id in tasks.first { $0.id == id } }
      ?? tasks.max { $0.openedAt < $1.openedAt }
    guard let task else { return false }

    task.controller.bringToFront()
    markTaskActive(task)
    return true
  }

  /// Voice input follows the user's active task instead of leaking text into a
  /// different retained composer. A focused composer takes priority over the
  /// global App Shot Fn action.
  @discardableResult
  func prepareForVoiceInput(at location: NSPoint) -> Task {
    let task = lastActiveTaskID.flatMap { id in tasks.first { $0.id == id } }
      ?? tasks.last(where: { $0.controller.isFrontmost })
      ?? tasks.last(where: { $0.controller.isVisible })
      ?? tasks.max { $0.openedAt < $1.openedAt }

    guard let task else {
      return openNewTask(at: location)
    }

    task.controller.bringToFront()
    markTaskActive(task)
    return task
  }

  private func markTaskActive(_ task: Task) {
    lastActiveTaskID = task.id
  }

}
