import SwiftUI

struct RouterTestResultView: View {
  let result: RouterEvaluation
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Divider()
      if let classification = result.classification {
        LabeledContent("Task type", value: classification.kind.title)
        LabeledContent("Complexity", value: classification.complexity.capitalized)
        LabeledContent("Task classification confidence", value: "\(Int(classification.confidence * 100))%")
        LabeledContent("Complexity confidence", value: "\(Int(classification.effortConfidence * 100))%")
        LabeledContent("Jev model-choice confidence", value: "\(Int(classification.modelConfidence * 100))%")
        LabeledContent("Decision model", value: classification.decisionModel)
      } else {
        Text("Classification unavailable").fontWeight(.medium)
      }
      if let selection = result.selection {
        LabeledContent("Agent", value: AgentProvider.displayName(for: selection.preset.agent))
        LabeledContent("Model", value: selection.preset.model ?? "Agent default")
        LabeledContent("Reasoning", value: selection.preset.effort?.capitalized ?? "Agent default")
        if result.usedFallback { Label("Would use your configured fallback", systemImage: "arrow.uturn.backward") }
      } else {
        Label("Would stop before starting an agent", systemImage: "stop.circle")
      }
      Text(result.summary).foregroundStyle(theme.secondaryTextColor).fixedSize(horizontal: false, vertical: true)
    }.font(.appFont(size: 11)).textSelection(.enabled)
  }
}
