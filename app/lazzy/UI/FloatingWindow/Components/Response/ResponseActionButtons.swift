import AppKit
import SwiftUI

struct ResponseActionButtons: View {
  let text: String
  let responseID: String
  var canBranch = false
  var onBranch: (() -> Void)? = nil
  @ObservedObject private var speech = ResponseSpeechController.shared
  @ObservedObject private var theme = ThemeManager.shared

  private var isReading: Bool { speech.speakingID == responseID }

  var body: some View {
    HStack(spacing: 6) {
      Button {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
      } label: {
        // Label("Copy", systemImage: "doc.on.doc").font(.appFont(size: 11))
      }.buttonStyle(.plain).help("Copy to clipboard").accessibilityLabel("Copy response")

      icon(isReading ? "stop.fill" : "speaker.wave.2", label: isReading ? "Stop reading" : "Read aloud") {
        speech.toggle(text: text, id: responseID)
      }.foregroundStyle(isReading ? theme.textColor : theme.secondaryTextColor)

      icon("arrow.triangle.branch", label: "Branch in new chat") { onBranch?() }
        .disabled(!canBranch || onBranch == nil)
        .help(canBranch ? "Branch in new chat" : "Branching is available after the reply finishes, for agents that support it.")
    }
    .foregroundStyle(theme.secondaryTextColor)
    .onChange(of: responseID) { oldID, _ in if speech.speakingID == oldID { speech.stop() } }
    .onDisappear { if isReading { speech.stop() } }
  }

  private func icon(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 12)).frame(width: 26, height: 26).contentShape(Rectangle())
    }.buttonStyle(.plain).help(label).accessibilityLabel(label)
  }
}
