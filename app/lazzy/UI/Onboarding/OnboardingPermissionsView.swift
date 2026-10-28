import SwiftUI

struct OnboardingPermissionsView: View {
  @StateObject private var permissions = PermissionsManager()

  var body: some View {
    VStack(spacing: 0) {
      permissionRow(
        title: "Accessibility",
        detail: "Read selected text and interact with native apps when requested.",
        isAllowed: permissions.hasAccessibilityPermission,
        action: permissions.requestAccessibilityPermission
      )
      Divider().opacity(0.2)
      permissionRow(
        title: "Screen recording",
        detail: "Capture a screen or app when you ask an agent to inspect it.",
        isAllowed: permissions.hasScreenCapturePermission,
        action: permissions.requestScreenCapturePermission
      )
    }
    .padding(.horizontal, 18)
    // .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    // .overlay {
    //   RoundedRectangle(cornerRadius: 16, style: .continuous)
    //     .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    // }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      permissions.checkPermissions()
    }
  }

  private func permissionRow(
    title: String,
    detail: String,
    isAllowed: Bool,
    action: @escaping () -> Void
  ) -> some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(OnboardingWelcomeFonts.inter(size: 14))
        Text(detail)
          .font(OnboardingWelcomeFonts.inter(size: 12))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Button(isAllowed ? "Allowed" : "Enable", action: action)
        .buttonStyle(OnboardingActionButtonStyle(isPrimary: false))
        .disabled(isAllowed)
    }
    .padding(.vertical, 14)
  }
}
