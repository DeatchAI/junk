import AppKit
import SwiftUI

struct ComposerFollowUpChip: View {
  let message: ChatMessage
  let number: Int
  let isSelected: Bool
  let canRevise: Bool
  var onSelect: () -> Void
  var onRevise: () -> Void
  @State private var isPresented = false
  @State private var hoverTask: Task<Void, Never>?
  @State private var keyboardPreview = false
  @FocusState private var isFocused: Bool
  @ObservedObject private var theme = ThemeManager.shared

  private var canEdit: Bool { canRevise && message.branchReference?.canBranch == true }

  var body: some View {
    Button(action: onSelect) {
      Text("\(number)")
        .font(.appFont(size: 11, weight: .medium))
        .foregroundStyle(isSelected ? theme.textColor : theme.secondaryTextColor)
        .frame(minWidth: 28, minHeight: 25)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .focusable()
    .focusEffectDisabled()
    .focused($isFocused)
    .themedSurface(in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(theme.textColor.opacity(isSelected ? 0.18 : 0.04), lineWidth: 0.7)
        .allowsHitTesting(false)
    }
    .onHover { hovering in
      hoverTask?.cancel()
      if hovering {
        hoverTask = Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(260))
          guard !Task.isCancelled else { return }
          keyboardPreview = false
          isPresented = true
        }
      }
    }
    .onChange(of: isFocused) { _, focused in
      if focused { keyboardPreview = true; isPresented = true }
    }
    .onDisappear { hoverTask?.cancel() }
    .accessibilityLabel("Show response to message \(number)")
    .accessibilityAction(named: Text("Preview message")) {
      keyboardPreview = true
      isPresented = true
    }
    .accessibilityAction(named: Text("Edit message")) {
      if canEdit { isPresented = false; onRevise() }
    }
    .background {
      DropdownPanelAnchor(isPresented: $isPresented, menuWidth: 370,
        menu: ComposerSentMessagePreview(message: message, number: number, canRevise: canEdit) {
          isPresented = false
          onRevise()
        }, opensOnHover: !keyboardPreview, acceptsKeyboardInput: keyboardPreview)
    }
  }
}

struct ComposerSentMessagePreview: View {
  let message: ChatMessage
  let number: Int
  let canRevise: Bool
  var onRevise: () -> Void
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Message \(number)")
          .font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor)
        Spacer()
        Button(action: onRevise) {
          Image(systemName: "pencil").font(.system(size: 12)).frame(width: 24, height: 24)
        }
        .buttonStyle(.plain).foregroundStyle(theme.secondaryTextColor)
        .disabled(!canRevise)
        .accessibilityLabel("Edit message \(number)")
        .help(canRevise ? "Edit in a new branch" : "Branching is unavailable while the agent is working or for this message")
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          let attachments = message.attachments.filter(\.isAvailable)
          if !attachments.isEmpty {
            ComposerAttachmentList(attachments: attachments)
          }
          let prompt = ConversationPrompt.readable(message.userPrompt)
          if !prompt.isEmpty {
            Text(verbatim: prompt)
              .font(.appFont(size: 12, weight: .regular))
              .foregroundStyle(theme.textColor.opacity(0.85))
              .lineSpacing(3)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding(.trailing, 2)
      }
      .frame(maxHeight: 235)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .frame(width: 362)
    .themedSurface(in: RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12).strokeBorder(theme.textColor.opacity(0.12), lineWidth: 0.7)
    }
    .padding(4)
  }
}
