import AppKit
import SwiftUI

struct MessagesPairingQRCode: View {
  let session: MessagesPairingSession
  let onCancel: () -> Void
  var onChangeAddress: (() -> Void)? = nil
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    VStack(spacing: 16) {
      Text("Scan to connect").font(.appFont(size: 18, weight: .semibold))
      if let image = MessagesQRCode.image(for: session.composeURL.absoluteString) {
        Image(decorative: image, scale: 1)
          .interpolation(.none).resizable().scaledToFit()
          .frame(width: 240, height: 240)
          .padding(18).background(Color.white, in: RoundedRectangle(cornerRadius: 12))
          .accessibilityLabel("QR code to pair Messages Remote")
      }
      Text("Scan with your iPhone Camera.\nOpen Messages, then tap Send.")
        .font(.appFont(size: 12)).foregroundStyle(theme.secondaryTextColor)
        .multilineTextAlignment(.center).lineSpacing(4)
      HStack(spacing: 8) {
        Text(session.agentAddress).lineLimit(1).truncationMode(.middle)
        if let onChangeAddress {
          Button("Change", action: onChangeAddress).buttonStyle(AppButtonStyle(kind: .quiet))
        }
      }.font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor)
      TimelineView(.periodic(from: .now, by: 1)) { context in
        let seconds = max(0, Int(session.expiresAt.timeIntervalSince(context.date)))
        Text("Expires in \(seconds / 60):\(String(format: "%02d", seconds % 60))")
          .font(.appFont(size: 10.5, design: .monospaced)).foregroundStyle(theme.secondaryTextColor)
      }
      AppDisclosure("Can’t scan?") {
        VStack(alignment: .leading, spacing: 8) {
          Text("Send this text to \(session.agentAddress). If the scan opens an empty draft, paste it into Messages.")
            .font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor)
          Text(session.messageText).font(.appFont(size: 10.5, design: .monospaced))
            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
          Button("Copy pairing text") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(session.messageText, forType: .string)
          }.buttonStyle(AppButtonStyle())
        }
      }.frame(maxWidth: 360, alignment: .leading)
      Button("Cancel", action: onCancel).buttonStyle(AppButtonStyle(kind: .quiet))
    }.frame(maxWidth: .infinity)
  }
}
