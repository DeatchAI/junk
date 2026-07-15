//
//  ShortcutsSettingsView.swift
//  lazzy
//
//  Settings view for configuring keyboard shortcuts
//

import Carbon.HIToolbox
import SwiftUI

struct ShortcutsSettingsView: View {
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        // Header
        VStack(alignment: .leading, spacing: 8) {
          Text("Keyboard Shortcuts")
            // .font(.appFont(size: 24, weight: .bold))
            .font(.custom("Sick-Regular", size: 24))
            .foregroundColor(theme.textColor)

          Text("Customize how you trigger Detach features and control the chat interface.")
            .font(.appFont(size: 13))
            .foregroundColor(theme.secondaryTextColor)
            .lineSpacing(4)
        }
        .padding(.bottom, 8)

        VStack(alignment: .leading, spacing: 32) {
          // Global Shortcuts
          ShortcutSection(title: "GLOBAL SHORTCUTS") {
            ShortcutRow(
              title: "Show Quick Actions",
              description: "Open the menu based on selection",
              shortcut: .init(
                get: { ShortcutSettings.quickActions },
                set: { ShortcutSettings.quickActions = $0 }
              ),
              isLast: false
            )

            ShortcutRow(
              title: "Show Floating AI Chat",
              description: "Toggle the main chat window",
              shortcut: .init(
                get: { ShortcutSettings.floatingChat },
                set: { ShortcutSettings.floatingChat = $0 }
              ),
              isLast: false
            )

            ShortcutRow(
              title: "Show Conversation History",
              description: "Open the history side panel",
              shortcut: .init(
                get: { ShortcutSettings.historyPanel },
                set: { ShortcutSettings.historyPanel = $0 }
              ),
              isLast: true
            )
          }

          // Chat Settings
          ShortcutSection(title: "CHAT ROOM") {
            ShortcutRow(
              title: "Submit Prompt",
              description: "Send message to AI",
              shortcut: .init(
                get: { ShortcutSettings.chatSubmit },
                set: { ShortcutSettings.chatSubmit = $0 }
              ),
              isLast: false
            )

            ShortcutRow(
              title: "New Chat",
              description: "Clear current conversation",
              shortcut: .init(
                get: { ShortcutSettings.chatNewChat },
                set: { ShortcutSettings.chatNewChat = $0 }
              ),
              isLast: true
            )
          }
        }

        // Safe bottom padding for scroll content
        Color.clear.frame(height: 20)

        // Reset Button
        HStack {
          Spacer()
          Button(action: { ShortcutSettings.resetToDefaults() }) {
            Text("Reset to Defaults")
              .font(.appFont(size: 12))
              .foregroundColor(theme.secondaryTextColor)
          }
          .buttonStyle(.plain)
        }
        .padding(.top, 16)
      }
    }
  }
}

// MARK: - Components

struct ShortcutSection<Content: View>: View {
  let title: String
  let content: Content
  @ObservedObject private var theme = ThemeManager.shared

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(title)
        .font(.appFont(size: 11, weight: .bold))
        .foregroundColor(theme.secondaryTextColor)
        .tracking(1)

      VStack(spacing: 0) {
        content
      }
      .background(theme.textColor.opacity(0.02))
      .cornerRadius(theme.borderRadius / 1.5)
      .overlay(
        RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
          .stroke(theme.borderColor.opacity(0.5), lineWidth: 0.5)
      )
    }
  }
}

struct ShortcutRow: View {
  let title: String
  let description: String
  @Binding var shortcut: KeyShortcut
  let isLast: Bool

  @ObservedObject private var theme = ThemeManager.shared
  @State private var isRecording = false

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.appFont(size: 14, weight: .semibold))
            .foregroundColor(theme.textColor)

          Text(description)
            .font(.appFont(size: 12))
            .foregroundColor(theme.secondaryTextColor)
        }

        Spacer()

        ShortcutRecorderView(shortcut: $shortcut, isRecording: $isRecording)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)

      if !isLast {
        Divider()
          .padding(.horizontal, 16)
          .opacity(0.3)
      }
    }
  }
}

struct ShortcutRecorderView: View {
  @Binding var shortcut: KeyShortcut
  @Binding var isRecording: Bool

  @ObservedObject private var theme = ThemeManager.shared
  @State private var hover = false

  var body: some View {
    Button(action: { isRecording = true }) {
      Text(isRecording ? "Type Shortcut..." : shortcut.displayString)
        .font(.appFont(size: 12, design: .monospaced))
        .foregroundColor(isRecording ? theme.accentColor : theme.textColor)
        .frame(minWidth: 100)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
          RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
            .fill(isRecording ? theme.accentColor.opacity(0.1) : theme.textColor.opacity(0.05))
        )
        .overlay(
          RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
            .stroke(isRecording ? theme.accentColor : theme.borderColor, lineWidth: 0.5)
        )
    }
    .buttonStyle(.plain)
    .onHover { hover = $0 }
    .overlay(
      // Weightless overlay to handle key events without affecting parent layout
      KeyEventHandlingView(isRecording: $isRecording) { newShortcut in
        DispatchQueue.main.async {
          shortcut = newShortcut
          isRecording = false
        }
      }
      .frame(width: 0, height: 0)
    )
  }
}

// Transparent view to catch key events when recording
struct KeyEventHandlingView: NSViewRepresentable {
  @Binding var isRecording: Bool
  var onRecorded: (KeyShortcut) -> Void

  func makeNSView(context: Context) -> NSView {
    let view = ShortcutNSView()
    view.onRecorded = onRecorded
    view.isRecording = $isRecording
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    if let view = nsView as? ShortcutNSView {
      view.isRecording = $isRecording
      if isRecording {
        view.setupMonitor()
      } else {
        view.stopMonitor()
      }
    }
  }

  class ShortcutNSView: NSView {
    var onRecorded: ((KeyShortcut) -> Void)?
    var isRecording: Binding<Bool>?
    private var eventMonitor: Any?

    func setupMonitor() {
      guard eventMonitor == nil else { return }

      eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self = self, self.isRecording?.wrappedValue == true else { return event }

        let modifiers = event.modifierFlags

        // Convert NSEvent.ModifierFlags to Carbon modifiers
        var carbonModifiers: Int = 0
        if modifiers.contains(.shift) { carbonModifiers |= shiftKey }
        if modifiers.contains(.control) { carbonModifiers |= controlKey }
        if modifiers.contains(.option) { carbonModifiers |= optionKey }
        if modifiers.contains(.command) { carbonModifiers |= cmdKey }

        let shortcut = KeyShortcut(keyCode: Int(event.keyCode), modifiers: carbonModifiers)

        self.onRecorded?(shortcut)

        return nil  // Consume the event
      }
    }

    func stopMonitor() {
      if let monitor = eventMonitor {
        NSEvent.removeMonitor(monitor)
        eventMonitor = nil
      }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
      if newWindow == nil {
        stopMonitor()
      }
    }

    deinit {
      stopMonitor()
    }
  }
}

// MARK: - Previews

#Preview {
  ShortcutsSettingsView()
    .padding()
    .frame(width: 500, height: 600)
    .background(Color(white: 0.05))
}
