import SwiftUI

struct AgentActivityText: View {
  let activity: String
  var fontSize: CGFloat = 11
  var isActive: Bool = true
  var event: AgentActivityEvent?
  var toolName: String?

  @ObservedObject private var theme = ThemeManager.shared

  @ViewBuilder
  var body: some View {
    let presentation = ActivityPresentationRegistry.presentation(
      status: activity,
      event: event,
      toolName: toolName
    )
    let failed = event?.phase == "failed"
    let content = HStack(alignment: .center, spacing: 9) {
      if let iconAsset = presentation.iconAsset {
        Image(iconAsset)
          .renderingMode(.template)
          .resizable()
          .scaledToFit()
          .frame(width: 17, height: 17)
          .foregroundStyle(failed ? Color.red : theme.textColor.opacity(0.88))
          .accessibilityHidden(true)
      } else {
        // TODO(activity-generic-animation): Replace generic prepare/working/thinking
        // states with the custom animated element requested for this surface.
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(presentation.title)
          .font(.appFont(size: fontSize, weight: .medium))
          .foregroundColor(failed ? .red : theme.textColor.opacity(isActive ? 0.84 : 0.58))
          .lineLimit(1)

        if let subtitle = presentation.subtitle {
          Text(subtitle)
            .font(.appFont(size: max(fontSize - 1, 10), weight: .regular))
            .foregroundColor(failed ? .red.opacity(0.78) : theme.secondaryTextColor.opacity(0.82))
            .lineLimit(1)
        }
      }
      .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      presentation.subtitle.map { "\(presentation.title), \($0)" } ?? presentation.title
    )
    .id(event?.id.map { "\($0):\(event?.phase ?? "")" } ?? presentation.title)

    if isActive && !failed {
      content.shimmer()
    } else {
      content
    }
  }
}
