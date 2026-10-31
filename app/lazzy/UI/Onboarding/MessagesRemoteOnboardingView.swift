import SwiftUI

struct MessagesRemoteOnboardingView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      setupRow("1", title: "Use an agent-only iMessage identity", detail: "Sign Messages on this Mac into a new Apple Account. Keep your personal account on your iPhone.")
      setupRow("2", title: "Connect your phone", detail: "In Settings → Messages Remote, scan the QR code with your iPhone and send the pairing message.")
      setupRow("3", title: "Text to manage work", detail: "Hear when tasks finish or need a decision, across every project. Answer questions, approve a pending request, and continue or stop an existing task.")
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
  }

  private func setupRow(_ number: String, title: String, detail: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text(number)
        .font(OnboardingWelcomeFonts.inter(size: 12).weight(.semibold))
        .frame(width: 24, height: 24)
        .background(Color.primary.opacity(0.08), in: Circle())
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(OnboardingWelcomeFonts.inter(size: 13).weight(.semibold))
        Text(detail).font(OnboardingWelcomeFonts.inter(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}
