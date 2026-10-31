import SwiftUI

struct LicenseDeactivateButton: View {
  @ObservedObject private var license = LicenseManager.shared
  @State private var isConfirming = false

  var body: some View {
    Button("Deactivate this Mac") { isConfirming = true }
      .disabled(license.isWorking)
      .confirmationDialog("Deactivate Detach on this Mac?", isPresented: $isConfirming) {
        Button("Deactivate") { Task { await license.deactivate() } }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This releases this Mac's activation. Your conversations and agent accounts stay on your Mac.")
      }
  }
}
