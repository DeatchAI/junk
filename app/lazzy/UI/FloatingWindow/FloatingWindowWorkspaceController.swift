import AppKit
import Combine
import Foundation

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
  /// The notch is only useful after every floating chat panel is closed. This
  /// deliberately uses visibility rather than key-window status: a visible
  /// chat still gives the user a full activity surface even when it is not key.
  @Published private(set) var isAnyComposerVisible = false
  private var lastActiveTaskID: Task.ID?

  var configureTask: ((Task) -> Void)?
  var onTaskCreated: ((Task) -> Void)?

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

    controller.onDismiss = { [weak self] in
      self?.refreshComposerVisibility()
    }
    controller.onVisibilityChanged = { [weak self, weak task] in
      guard let self, let task else { return }
      if controller.isVisible {
        self.markTaskActive(task)
      }
      self.refreshComposerVisibility()
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
    refreshComposerVisibility()
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
    refreshComposerVisibility()
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
    refreshComposerVisibility()
    return true
  }

  private func markTaskActive(_ task: Task) {
    lastActiveTaskID = task.id
  }

  private func refreshComposerVisibility() {
    let value = tasks.contains { $0.controller.isVisible }
    if isAnyComposerVisible != value {
      isAnyComposerVisible = value
    }
  }
}
