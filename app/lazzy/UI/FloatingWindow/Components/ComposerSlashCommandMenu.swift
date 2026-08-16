import AppKit
import SwiftUI

struct ComposerSlashCommandMenu: View {
  let query: String
  let workflows: [QuickAction]
  let quickActions: [QuickAction]
  let onSelectAlias: (SlashCommandAlias) -> Void
  let onSelectAction: (QuickAction) -> Void
  let onCreateCommand: (String, String) -> Void
  let onOpenDestination: (ComposerCommandDestination) -> Void
  let onDismiss: () -> Void

  @ObservedObject private var theme = ThemeManager.shared
  @State private var selectedIndex = 0
  @State private var keyMonitor: Any?
  @State private var isCreatingCommand = false
  @State private var newCommandName = ""
  @State private var newCommandPrompt = ""
  @FocusState private var focusedCreateField: CreateCommandField?

  private enum CreateCommandField {
    case name
    case prompt
  }

  private var normalizedQuery: String {
    query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private var visibleItems: [SlashCommandMenuItem] {
    var items: [SlashCommandMenuItem] = []
    items.append(contentsOf: visibleWorkflows.map(SlashCommandMenuItem.workflow))
    items.append(contentsOf: visibleQuickActions.map(SlashCommandMenuItem.quickAction))
    items.append(contentsOf: visibleAliases.map(SlashCommandMenuItem.alias))
    items.append(contentsOf: visibleCreateItems)
    return items
  }

  private var visibleWorkflows: [QuickAction] {
    filtered(workflows.filter(\.enabled))
  }

  private var visibleQuickActions: [QuickAction] {
    filtered(quickActions.filter(\.enabled))
  }

  private var visibleAliases: [SlashCommandAlias] {
    SlashCommandAlias.defaults.filter { matches($0.command) || matches($0.title) || matches($0.subtitle) }
  }

  private var visibleDestinations: [SlashCommandDestinationItem] {
    SlashCommandDestinationItem.defaults.filter { matches($0.command) || matches($0.title) || matches($0.subtitle) }
  }

  private var visibleCreateItems: [SlashCommandMenuItem] {
    var items: [SlashCommandMenuItem] = []
    if matches("new command") || matches("create command") {
      items.append(.inlineCreateCommand)
    }
    items.append(contentsOf: visibleDestinations.map(SlashCommandMenuItem.destination))
    return items
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      if isCreatingCommand {
        createCommandForm
      } else if visibleItems.isEmpty {
        ComposerAttachmentMenuEmptyState(text: "No matching commands")
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 8) {
            commandSection(
              title: "Workflows",
              items: visibleWorkflows.map(SlashCommandMenuItem.workflow)
            )
            commandSection(
              title: "Quick Actions",
              items: visibleQuickActions.map(SlashCommandMenuItem.quickAction)
            )
            commandSection(
              title: "Commands",
              items: visibleAliases.map(SlashCommandMenuItem.alias)
            )
            commandSection(
              title: "Create",
              items: visibleCreateItems
            )
          }
        }
        .frame(maxHeight: 338)
      }
    }
    .padding(6)
    .frame(width: 320, alignment: .leading)
    .background(menuBackground)
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(theme.textColor.opacity(0.1), lineWidth: 0.5)
    }
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .onAppear(perform: setupKeyMonitor)
    .onDisappear(perform: removeKeyMonitor)
    .onChange(of: query) { _, _ in clampSelection() }
    .onChange(of: workflows.count) { _, _ in clampSelection() }
    .onChange(of: quickActions.count) { _, _ in clampSelection() }
    .onChange(of: isCreatingCommand) { _, isCreating in
      clampSelection()
      if isCreating {
        DispatchQueue.main.async {
          focusedCreateField = .name
        }
      }
    }
  }

  private var createCommandForm: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Button(action: closeCreateCommandForm) {
          Image(systemName: "chevron.left")
            .font(.appFont(size: 11, weight: .semibold))
            .frame(width: 24, height: 28)
        }
        .buttonStyle(.plain)
        .help("Back")

        Text("New Command")
          .font(.appFont(size: 13, weight: .semibold))
        Spacer()
      }
      .foregroundColor(theme.textColor)
      .padding(.horizontal, 4)

      VStack(alignment: .leading, spacing: 8) {
        slashCommandTextField(
          title: "Name",
          text: $newCommandName,
          placeholder: "summarize",
          field: .name
        )
        slashCommandTextField(
          title: "Prompt",
          text: $newCommandPrompt,
          placeholder: "Summarize this clearly",
          field: .prompt
        )
      }

      HStack(spacing: 8) {
        Button("Cancel", action: closeCreateCommandForm)
          .buttonStyle(.plain)
          .font(.appFont(size: 12, weight: .medium))
          .foregroundColor(theme.secondaryTextColor)

        Spacer()

        Button(action: saveCommand) {
          HStack(spacing: 5) {
            Image(systemName: "plus")
            Text("Create")
          }
          .font(.appFont(size: 12, weight: .semibold))
          .foregroundColor(theme.backgroundColor)
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(canSaveCommand ? theme.accentColor : theme.textColor.opacity(0.16))
          .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSaveCommand)
      }
      .padding(.horizontal, 4)
    }
    .padding(5)
  }

  private func slashCommandTextField(
    title: String,
    text: Binding<String>,
    placeholder: String,
    field: CreateCommandField
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.appFont(size: 11, weight: .medium))
        .foregroundColor(theme.secondaryTextColor)
      TextField(placeholder, text: text)
        .textFieldStyle(.plain)
        .font(.appFont(size: 13))
        .foregroundColor(theme.textColor)
        .focused($focusedCreateField, equals: field)
        .onSubmit {
          if field == .name {
            focusedCreateField = .prompt
          } else {
            saveCommand()
          }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(theme.textColor.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
    .padding(.horizontal, 4)
  }

  @ViewBuilder
  private func commandSection(
    title: String,
    items: [SlashCommandMenuItem]
  ) -> some View {
    if !items.isEmpty {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.appFont(size: 12, weight: .medium))
          .foregroundColor(theme.secondaryTextColor)
          .padding(.horizontal, 10)
          .padding(.top, 2)

        ForEach(items) { item in
          ComposerAttachmentMenuRow(
            title: item.title,
            subtitle: item.subtitle,
            systemImage: item.systemImage,
            isHighlighted: selectedIndex == globalIndex(for: item),
            onHover: {
              selectedIndex = globalIndex(for: item)
            }
          ) {
            activate(item)
          }
        }

      }
    }
  }

  @ViewBuilder
  private var menuBackground: some View {
    if theme.usesGlassEffect {
      ZStack {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(.ultraThinMaterial)
        if let overlay = theme.glassOverlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(overlay)
        }
      }
    } else {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(theme.solidBackground)
    }
  }

  private func filtered(_ actions: [QuickAction]) -> [QuickAction] {
    actions.filter { action in
      matches(action.title) || matches(action.prompt ?? "") || matches(action.shortcut ?? "")
    }
  }

  private func matches(_ text: String) -> Bool {
    normalizedQuery.isEmpty || text.lowercased().contains(normalizedQuery)
  }

  private func globalIndex(for item: SlashCommandMenuItem) -> Int {
    visibleItems.firstIndex(where: { $0.id == item.id }) ?? 0
  }

  private func setupKeyMonitor() {
    guard keyMonitor == nil else { return }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      guard !isCreatingCommand else { return event }
      let modifiers = event.modifierFlags.intersection([.command, .option, .control])
      guard modifiers.isEmpty else { return event }

      switch Int(event.keyCode) {
      case 125:
        moveSelection(by: 1)
        return nil
      case 126:
        moveSelection(by: -1)
        return nil
      case 36, 76:
        activateSelected()
        return nil
      case 53:
        onDismiss()
        return nil
      default:
        return event
      }
    }
  }

  private func removeKeyMonitor() {
    if let keyMonitor {
      NSEvent.removeMonitor(keyMonitor)
      self.keyMonitor = nil
    }
  }

  private func moveSelection(by delta: Int) {
    guard !visibleItems.isEmpty else { return }
    selectedIndex = min(max(selectedIndex + delta, 0), visibleItems.count - 1)
  }

  private func clampSelection() {
    guard !visibleItems.isEmpty else {
      selectedIndex = 0
      return
    }
    selectedIndex = min(max(selectedIndex, 0), visibleItems.count - 1)
  }

  private func activateSelected() {
    guard visibleItems.indices.contains(selectedIndex) else { return }
    activate(visibleItems[selectedIndex])
  }

  private func activate(_ item: SlashCommandMenuItem) {
    switch item {
    case .inlineCreateCommand:
      isCreatingCommand = true
    case .workflow(let action), .quickAction(let action):
      onSelectAction(action)
    case .alias(let alias):
      onSelectAlias(alias)
    case .destination(let destination):
      onOpenDestination(destination.destination)
    }
  }

  private var canSaveCommand: Bool {
    !newCommandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !newCommandPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func saveCommand() {
    let name = newCommandName.trimmingCharacters(in: .whitespacesAndNewlines)
    let prompt = newCommandPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !prompt.isEmpty else { return }
    onCreateCommand(name, prompt)
  }

  private func closeCreateCommandForm() {
    isCreatingCommand = false
    newCommandName = ""
    newCommandPrompt = ""
  }
}

private enum SlashCommandMenuItem: Identifiable {
  case inlineCreateCommand
  case workflow(QuickAction)
  case quickAction(QuickAction)
  case alias(SlashCommandAlias)
  case destination(SlashCommandDestinationItem)

  var id: String {
    switch self {
    case .inlineCreateCommand:
      return "inline-create-command"
    case .workflow(let action):
      return "workflow:\(action.id)"
    case .quickAction(let action):
      return "quick-action:\(action.id)"
    case .alias(let alias):
      return "alias:\(alias.id)"
    case .destination(let destination):
      return "destination:\(destination.id)"
    }
  }

  var title: String {
    switch self {
    case .inlineCreateCommand:
      return "New Command"
    case .workflow(let action), .quickAction(let action):
      return action.title
    case .alias(let alias):
      return alias.title
    case .destination(let destination):
      return destination.title
    }
  }

  var subtitle: String? {
    switch self {
    case .inlineCreateCommand:
      return "Create a reusable command here"
    case .workflow(let action), .quickAction(let action):
      return action.prompt
    case .alias(let alias):
      return "/\(alias.command) - \(alias.subtitle)"
    case .destination(let destination):
      return destination.subtitle
    }
  }

  var systemImage: String {
    switch self {
    case .inlineCreateCommand:
      return "plus.circle"
    case .workflow(let action), .quickAction(let action):
      return action.systemImage ?? (action.kind == "workflow" ? "play.square.stack" : "bolt")
    case .alias(let alias):
      return alias.systemImage
    case .destination(let destination):
      return destination.systemImage
    }
  }
}

private struct SlashCommandDestinationItem: Identifiable {
  let id: String
  let command: String
  let title: String
  let subtitle: String
  let systemImage: String
  let destination: ComposerCommandDestination

  static let defaults: [SlashCommandDestinationItem] = [
    SlashCommandDestinationItem(
      id: "create-workflow",
      command: "create-workflow",
      title: "Create Workflow",
      subtitle: "Open the workflow builder",
      systemImage: "plus.square.on.square",
      destination: .createWorkflow
    ),
    SlashCommandDestinationItem(
      id: "create-quick-action",
      command: "create-quick-action",
      title: "Create Quick Action",
      subtitle: "Open the quick action builder",
      systemImage: "bolt.badge.plus",
      destination: .createQuickAction
    ),
    SlashCommandDestinationItem(
      id: "connect-mcp",
      command: "connect-mcp",
      title: "Connect MCP",
      subtitle: "Add a custom server or integration",
      systemImage: "server.rack",
      destination: .connectMCP
    ),
  ]
}
