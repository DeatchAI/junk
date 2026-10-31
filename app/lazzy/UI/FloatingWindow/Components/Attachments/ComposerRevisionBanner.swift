import SwiftUI

struct ComposerRevisionBanner: View {
  let messageNumber: Int
  var afterResponse = false
  var error: String? = nil
  var onCancel: () -> Void
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 5) {
        Image(systemName: afterResponse ? "arrow.triangle.branch" : "pencil").font(.system(size: 10))
        Text(afterResponse ? "New chat after reply \(messageNumber)" : "Editing message \(messageNumber)").font(.appFont(size: 11))
          .help("Sending creates a new conversation branch and preserves the original.")
        Spacer()
        Button("Cancel", action: onCancel).buttonStyle(.plain)
          .font(.appFont(size: 11))
          .help("Restore your previous draft")
      }
      if let error { Text(error).font(.appFont(size: 11)).fixedSize(horizontal: false, vertical: true) }
    }
    .foregroundStyle(theme.secondaryTextColor)
  }
}
