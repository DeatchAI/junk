import SwiftUI

struct LicenseKeyEntryForm: View {
  @ObservedObject private var license = LicenseManager.shared
  @State private var key = ""

  var body: some View {
    VStack(spacing: 14) {
      SecureField("License key", text: $key)
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.leading)
        .accessibilityLabel("Detach license key")
        .disabled(license.isWorking)
        .onSubmit(activate)
      Button(action: activate) {
        HStack(spacing: 8) {
          if license.isWorking { ProgressView().controlSize(.small) }
          Text(license.isWorking ? "Checking…" : "Unlock Detach")
        }
      }
      .disabled(license.isWorking || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      if let message = license.message {
        Text(message)
          .font(.appFont(size: 12))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .onDisappear { key = "" }
  }

  private func activate() {
    guard !license.isWorking, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    Task {
      await license.activate(key)
      if license.status == .licensed { key = "" }
    }
  }
}
