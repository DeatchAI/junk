#if DEBUG
import Foundation

struct DebugDemoScenario {
  let prompt: String
  let commandID: String
  let fixturePaths: [String]
  let mcpServerIDs: [String]
}

enum DebugDemoCatalog {
  static let browserMCPID = "detach-browser-tools"
  static let macOSMCPID = "detach-macos-tools"
  static let secretsMCPID = "detach-secrets-tools"

  static let scenarios = [
    DebugDemoScenario(
      prompt: "Review the attached checkout pull request, test changes, and CI notes for bugs, regressions, and missing tests.",
      commandID: "code-review",
      fixturePaths: [
        "checkout-review",
        "checkout-review/checkout-pr.patch",
        "checkout-review/checkout-payment-test.ts",
        "checkout-review/ci-notes.md",
      ],
      mcpServerIDs: []
    ),
    DebugDemoScenario(
      prompt: "Fix the failing tests in the attached project files, run the relevant checks, and show me the diff.",
      commandID: "debug",
      fixturePaths: [
        "test-fix-project",
        "test-fix-project/date-formatting-test.ts",
      ],
      mcpServerIDs: []
    ),
    DebugDemoScenario(
      prompt: "Open the staging checkout URL from the attached runbook, reproduce the payment bug, and tell me what broke.",
      commandID: "debug",
      fixturePaths: ["staging-checkout.md"],
      mcpServerIDs: [browserMCPID]
    ),
    DebugDemoScenario(
      prompt: "Use the attached pricing brief to compare the current plans for these tools and cite the live sources.",
      commandID: "plan",
      fixturePaths: ["pricing-brief.md"],
      mcpServerIDs: [browserMCPID]
    ),
    DebugDemoScenario(
      prompt: "Review the attached Downloads folder and propose a cleaner project-based organization without deleting anything.",
      commandID: "plan",
      fixturePaths: [
        "downloads-demo",
        "downloads-demo/acme-invoice.csv",
        "downloads-demo/detach-release-notes.md",
      ],
      mcpServerIDs: [macOSMCPID]
    ),
    DebugDemoScenario(
      prompt: "Build a small dashboard from the attached usage CSV and run it locally.",
      commandID: "plan",
      fixturePaths: ["usage-dashboard", "usage-dashboard/usage.csv"],
      mcpServerIDs: []
    ),
    DebugDemoScenario(
      prompt: "Log in to the admin dashboard and export this month's usage report using the attached report specification.",
      commandID: "plan",
      fixturePaths: ["report-spec.md"],
      mcpServerIDs: [browserMCPID, secretsMCPID]
    ),
    DebugDemoScenario(
      prompt: "Summarize the attached meeting transcript and turn the action items into a checklist.",
      commandID: "compact-context",
      fixturePaths: ["meeting-transcript.md"],
      mcpServerIDs: []
    ),
  ]

  static let chatPrompts = scenarios.map(\.prompt)

  static func scenario(for prompt: String) -> DebugDemoScenario? {
    scenarios.first { $0.prompt == prompt }
  }
}
#endif
