import SwiftUI

/// View to show command approval requests from the AI agent
struct CommandApprovalView: View {
  let requestId: String
  let command: String
  let description: String
  let riskLevel: String  // "safe", "normal", "dangerous"
  let onApprove: () -> Void
  let onDeny: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var timeRemaining = 60  // Auto-deny after 60 seconds
  @State private var timer: Timer?

  private var riskColor: Color {
    switch riskLevel {
    case "dangerous":
      return .red
    case "normal":
      return .orange
    default:
      return .green
    }
  }

  private var riskIcon: String {
    switch riskLevel {
    case "dangerous":
      return "exclamationmark.triangle.fill"
    case "normal":
      return "exclamationmark.circle.fill"
    default:
      return "checkmark.circle.fill"
    }
  }

  var body: some View {
    VStack(spacing: 16) {
      // Header
      HStack {
        Image(systemName: riskIcon)
          .font(.title2)
          .foregroundColor(riskColor)

        Text("Command Approval Required")
          .font(.headline)

        Spacer()

        // Countdown timer
        Text("\(timeRemaining)s")
          .font(.caption)
          .foregroundColor(.secondary)
          .monospacedDigit()
      }

      Divider()

      // Description
      Text(description)
        .font(.subheadline)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      // Command preview
      ScrollView {
        Text(command)
          .font(.system(.body, design: .monospaced))
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color(.textBackgroundColor).opacity(0.5))
          .cornerRadius(8)
      }
      .frame(maxHeight: 150)

      // Warning for dangerous commands
      if riskLevel == "dangerous" {
        HStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundColor(.red)
          Text(
            "This command may have destructive effects. Please review carefully before approving."
          )
          .font(.caption)
          .foregroundColor(.red)
        }
        .padding(10)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
      }

      Divider()

      // Action buttons
      HStack(spacing: 12) {
        Button(action: {
          timer?.invalidate()
          onDeny()
          dismiss()
        }) {
          HStack {
            Image(systemName: "xmark.circle.fill")
            Text("Deny")
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .tint(.red)

        Button(action: {
          timer?.invalidate()
          onApprove()
          dismiss()
        }) {
          HStack {
            Image(systemName: "checkmark.circle.fill")
            Text("Approve")
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(riskLevel == "dangerous" ? .orange : .green)
      }
    }
    .padding()
    .frame(width: 450)
    .onAppear {
      startTimer()
    }
    .onDisappear {
      timer?.invalidate()
    }
  }

  private func startTimer() {
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
      if timeRemaining > 0 {
        timeRemaining -= 1
      } else {
        timer?.invalidate()
        onDeny()  // Auto-deny on timeout
        dismiss()
      }
    }
  }
}

#Preview {
  CommandApprovalView(
    requestId: "test-123",
    command: "rm -rf ~/Desktop/test-folder",
    description: "Execute shell command: rm -rf ~/Desktop/test-folder",
    riskLevel: "dangerous",
    onApprove: { print("Approved") },
    onDeny: { print("Denied") }
  )
}
