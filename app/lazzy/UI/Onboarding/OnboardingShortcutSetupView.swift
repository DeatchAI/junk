import SwiftUI

struct OnboardingShortcutSetupView: View {
  private enum ShortcutField: Equatable {
    case showComposer, closeComposer, history, submit
  }

  @State private var recordingField: ShortcutField?

  var body: some View {
    VStack(spacing: 0) {
      shortcutRow(
        title: "Show composer",
        detail: "Open a new floating composer.",
        shortcut: binding(get: { ShortcutSettings.floatingChat }, set: { ShortcutSettings.floatingChat = $0 }),
        field: .showComposer
      )
      rowDivider
      shortcutRow(
        title: "Close composer",
        detail: "Dismiss the visible composer.",
        shortcut: binding(get: { ShortcutSettings.closeComposer }, set: { ShortcutSettings.closeComposer = $0 }),
        field: .closeComposer
      )
      rowDivider
      shortcutRow(
        title: "Open chat history",
        detail: "Browse your conversations.",
        shortcut: binding(get: { ShortcutSettings.historyPanel }, set: { ShortcutSettings.historyPanel = $0 }),
        field: .history
      )
      rowDivider
      shortcutRow(
        title: "Submit prompt",
        detail: "Send your message to the agent.",
        shortcut: binding(get: { ShortcutSettings.chatSubmit }, set: { ShortcutSettings.chatSubmit = $0 }),
        field: .submit
      )
    }
    .padding(.horizontal, 18)
    // .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    // .overlay {
    //   RoundedRectangle(cornerRadius: 16, style: .continuous)
    //     .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    // }
  }

  private var rowDivider: some View {
    Divider().opacity(0.2)
  }

  private func shortcutRow(
    title: String,
    detail: String,
    shortcut: Binding<KeyShortcut>,
    field: ShortcutField
  ) -> some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(OnboardingWelcomeFonts.inter(size: 14))
        Text(detail)
          .font(OnboardingWelcomeFonts.inter(size: 12))
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      ShortcutRecorderView(
        shortcut: shortcut,
        isRecording: recordingBinding(for: field),
        foregroundColor: .primary,
        accentColor: .primary
      )
    }
    .padding(.vertical, 13)
  }

  private func recordingBinding(for field: ShortcutField) -> Binding<Bool> {
    Binding(
      get: { recordingField == field },
      set: { recordingField = $0 ? field : nil }
    )
  }

  private func binding(
    get: @escaping () -> KeyShortcut,
    set: @escaping (KeyShortcut) -> Void
  ) -> Binding<KeyShortcut> {
    Binding(get: get, set: set)
  }
}
