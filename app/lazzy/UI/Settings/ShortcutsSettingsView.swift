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
        SettingsPageHeader(
          title: "Keyboard shortcuts",
          subtitle: "Customize how you open Detach and move through conversations."
        )

        VStack(alignment: .leading, spacing: 24) {
          // Global Shortcuts
          ShortcutSection(title: "Global") {
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
              title: "New Floating Chat",
              description: "Create a new floating agent task",
              shortcut: .init(
                get: { ShortcutSettings.floatingChat },
                set: { ShortcutSettings.floatingChat = $0 }
              ),
              isLast: false
            )

            ShortcutRow(
              title: "Resume Last Chat",
              description: "Bring your most recent task back to the front",
              shortcut: .init(
                get: { ShortcutSettings.resumeLastChat },
                set: { ShortcutSettings.resumeLastChat = $0 }
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
          ShortcutSection(title: "Conversation") {
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

        // Reset Button
        HStack {
          Spacer()
          Button(action: { ShortcutSettings.resetToDefaults() }) {
            Label("Reset shortcuts", systemImage: "arrow.counterclockwise")
              .font(.appFont(size: 11, weight: .medium))
              .foregroundColor(theme.secondaryTextColor)
          }
          .buttonStyle(.plain)
        }
        .padding(.top, 2)

        Color.clear.frame(height: 20)
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
    VStack(alignment: .leading, spacing: 10) {
      SettingsSectionHeader(title: title)

      SettingsCard {
        content
      }
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
          .opacity(0.22)
      }
    }
  }
}

struct ShortcutRecorderView: View {
  @Binding var shortcut: KeyShortcut
  @Binding var isRecording: Bool
  var foregroundColor: Color? = nil
  var accentColor: Color? = nil

  @ObservedObject private var theme = ThemeManager.shared
  @State private var hover = false

  var body: some View {
    let textColor = foregroundColor ?? theme.textColor
    let activeAccent = accentColor ?? theme.accentColor

    Button(action: { isRecording = true }) {
      Text(isRecording ? "Type Shortcut..." : shortcut.displayString)
        .font(.appFont(size: 12, design: .monospaced))
        .foregroundColor(isRecording ? activeAccent : textColor)
        .frame(minWidth: 100)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
          RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
            .fill(isRecording ? activeAccent.opacity(0.1) : textColor.opacity(0.05))
        )
        .overlay(
          RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
            .stroke(isRecording ? activeAccent : theme.borderColor, lineWidth: 0.5)
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
