import SwiftUI

struct WorkflowsSettingsView: View {
  @ObservedObject var wsManager: WebSocketManager
  var onRunWorkflow: ((QuickAction) -> Void)?

  @ObservedObject private var theme = ThemeManager.shared
  @State private var showForm = false
  @State private var editingWorkflow: QuickAction?

  init(
    wsManager: WebSocketManager,
    onRunWorkflow: ((QuickAction) -> Void)? = nil,
    startInCreateMode: Bool = false
  ) {
    self.wsManager = wsManager
    self.onRunWorkflow = onRunWorkflow
    _showForm = State(initialValue: startInCreateMode)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      VStack(alignment: .leading, spacing: 8) {
        Text("Workflows")
          .font(.custom("Sick-Regular", size: 24))
          .foregroundColor(theme.textColor)

        Text("Create reusable AI workflows that can run immediately without typing a new message.")
          .font(.appFont(size: 13))
          .foregroundColor(theme.secondaryTextColor)
          .lineSpacing(4)
      }
      .padding(.bottom, 8)

      if showForm || editingWorkflow != nil {
        WorkflowFormView(
          wsManager: wsManager,
          editingWorkflow: editingWorkflow,
          onDismiss: {
            withAnimation(.easeInOut) {
              showForm = false
              editingWorkflow = nil
            }
          }
        )
      } else {
        HStack {
          Spacer()
          Button(action: {
            withAnimation(.easeInOut) {
              showForm = true
            }
          }) {
            HStack(spacing: 4) {
              Image(systemName: "plus")
              Text("Add Workflow")
            }
            .font(.appFont(size: 12, weight: .semibold))
            .foregroundColor(theme.backgroundColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(theme.accentColor)
            .cornerRadius(theme.borderRadius / 1.5)
          }
          .buttonStyle(.plain)
        }

        if wsManager.workflows.isEmpty {
          VStack(spacing: 16) {
            Image(systemName: "play.square.stack")
              .font(.appFont(size: 48))
              .foregroundColor(theme.secondaryTextColor.opacity(0.5))
            Text("No Workflows Yet")
              .font(.appFont(size: 16, weight: .semibold))
              .foregroundColor(theme.secondaryTextColor)
            Text("Create workflows for prompts you want to run in one click")
              .font(.appFont(size: 13))
              .foregroundColor(theme.secondaryTextColor.opacity(0.7))
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 60)
        } else {
          ScrollView {
            VStack(spacing: 12) {
              ForEach(wsManager.workflows) { workflow in
                WorkflowRow(
                  workflow: workflow,
                  onRun: { onRunWorkflow?(workflow) },
                  onEdit: {
                    withAnimation(.easeInOut) {
                      editingWorkflow = workflow
                    }
                  },
                  onDelete: {
                    wsManager.deleteWorkflow(actionId: workflow.id)
                  }
                )
              }
            }
          }
        }
      }

      Spacer(minLength: 0)
    }
    .onAppear {
      wsManager.listWorkflows()
      wsManager.listMCPServers()
    }
  }
}

private struct WorkflowRow: View {
  let workflow: QuickAction
  let onRun: () -> Void
  let onEdit: () -> Void
  let onDelete: () -> Void

  @ObservedObject private var theme = ThemeManager.shared
  @State private var isHovered = false
  @State private var showDeleteConfirm = false

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
          .fill(theme.accentColor.opacity(0.15))
          .frame(width: 40, height: 40)
        Image(systemName: workflow.systemImage ?? "play.fill")
          .font(.appFont(size: 16))
          .foregroundColor(theme.accentColor)
      }

      VStack(alignment: .leading, spacing: 4) {
        Text(workflow.title)
          .font(.appFont(size: 14, weight: .semibold))
          .foregroundColor(theme.textColor)
        Text(workflow.prompt ?? "")
          .font(.appFont(size: 12))
          .foregroundColor(theme.secondaryTextColor)
          .lineLimit(1)
        if let mcpServerIds = workflow.mcpServerIds, !mcpServerIds.isEmpty {
          Text("\(mcpServerIds.count) MCP capability\(mcpServerIds.count == 1 ? "" : "s")")
            .font(.appFont(size: 10))
            .foregroundColor(theme.secondaryTextColor.opacity(0.75))
        }
      }

      Spacer()

      HStack(spacing: 8) {
        Button(action: onRun) {
          Image(systemName: "play.fill")
            .font(.appFont(size: 12))
            .foregroundColor(theme.backgroundColor)
            .padding(7)
            .background(theme.accentColor)
            .cornerRadius(theme.borderRadius / 2)
        }
        .buttonStyle(.plain)

        if isHovered {
          Button(action: onEdit) {
            Image(systemName: "pencil")
              .font(.appFont(size: 12))
              .foregroundColor(theme.textColor)
              .padding(7)
              .background(theme.textColor.opacity(0.1))
              .cornerRadius(theme.borderRadius / 2)
          }
          .buttonStyle(.plain)

          Button(action: { showDeleteConfirm = true }) {
            Image(systemName: "trash")
              .font(.appFont(size: 12))
              .foregroundColor(.red)
              .padding(7)
              .background(Color.red.opacity(0.1))
              .cornerRadius(theme.borderRadius / 2)
          }
          .buttonStyle(.plain)
        }
      }
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
        .fill(isHovered ? theme.textColor.opacity(0.05) : theme.textColor.opacity(0.02))
    )
    .overlay(
      RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
        .stroke(theme.borderColor.opacity(0.5), lineWidth: 0.5)
    )
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.15)) {
        isHovered = hovering
      }
    }
    .alert("Delete Workflow?", isPresented: $showDeleteConfirm) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive, action: onDelete)
    } message: {
      Text("This workflow cannot be undone.")
    }
  }
}

private struct WorkflowFormView: View {
  @ObservedObject var wsManager: WebSocketManager
  let editingWorkflow: QuickAction?
  let onDismiss: () -> Void

  @ObservedObject private var theme = ThemeManager.shared
  @State private var name = ""
  @State private var prompt = ""
  @State private var systemImage = "play.fill"
  @State private var selectedMCPServerIds = Set<String>()

  private var availableMCPOptions: [ActionMCPOption] {
    actionMCPOptions(
      from: wsManager.mcpServers,
      composioIntegrations: wsManager.composioIntegrations
    )
  }

  private var isEditing: Bool { editingWorkflow != nil }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        Text(isEditing ? "Edit Workflow" : "New Workflow")
          .font(.appFont(size: 16, weight: .semibold))
          .foregroundColor(theme.textColor)
        Spacer()
        Button(action: onDismiss) {
          HStack(spacing: 4) {
            Image(systemName: "chevron.left")
            Text("Back")
          }
          .font(.appFont(size: 13, weight: .medium))
          .foregroundColor(theme.secondaryTextColor)
        }
        .buttonStyle(.plain)
      }

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          labeledTextField("NAME", placeholder: "e.g., Check unread Gmail", text: $name)

          VStack(alignment: .leading, spacing: 8) {
            Text("PROMPT")
              .font(.appFont(size: 11, weight: .bold))
              .foregroundColor(theme.secondaryTextColor)
            TextEditor(text: $prompt)
              .font(.appFont(size: 13))
              .foregroundColor(theme.textColor)
              .scrollContentBackground(.hidden)
              .frame(minHeight: 110, maxHeight: 150)
              .padding(12)
              .background(theme.textColor.opacity(0.05))
              .cornerRadius(8)
              .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.borderColor, lineWidth: 0.5))
          }

          VStack(alignment: .leading, spacing: 8) {
            Text("MCP CAPABILITIES")
              .font(.appFont(size: 11, weight: .bold))
              .foregroundColor(theme.secondaryTextColor)

            VStack(spacing: 6) {
              ForEach(availableMCPOptions) { option in
                Button(action: { toggleMCPServer(option.serverId) }) {
                  HStack(spacing: 8) {
                    Image(
                      systemName: selectedMCPServerIds.contains(option.serverId)
                        ? "checkmark.circle.fill" : "circle"
                    )
                    .foregroundColor(
                      selectedMCPServerIds.contains(option.serverId)
                        ? theme.accentColor : theme.secondaryTextColor
                    )

                    Image(systemName: option.systemImage)
                      .font(.appFont(size: 12))
                      .foregroundColor(theme.secondaryTextColor)
                      .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                      Text(option.name)
                        .font(.appFont(size: 12, weight: .medium))
                      Text(option.detail)
                        .font(.appFont(size: 10))
                        .foregroundColor(theme.secondaryTextColor.opacity(0.8))
                        .lineLimit(1)
                    }

                    Spacer()
                  }
                  .foregroundColor(theme.textColor)
                  .padding(8)
                  .background(theme.textColor.opacity(0.04))
                  .cornerRadius(7)
                }
                .buttonStyle(.plain)
              }
            }
          }

          HStack {
            Spacer()
            Button(action: saveWorkflow) {
              Text(isEditing ? "Save Changes" : "Create Workflow")
                .font(.appFont(size: 14, weight: .semibold))
                .foregroundColor(theme.backgroundColor)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                  RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
                    .fill(name.isEmpty || prompt.isEmpty ? theme.accentColor.opacity(0.5) : theme.accentColor)
                )
            }
            .buttonStyle(.plain)
            .disabled(name.isEmpty || prompt.isEmpty)
            Spacer()
          }
        }
      }
    }
    .onAppear {
      wsManager.listMCPServers()
      wsManager.listComposioIntegrations(limit: 100)
      if let workflow = editingWorkflow {
        name = workflow.title
        prompt = workflow.prompt ?? ""
        systemImage = workflow.systemImage ?? "play.fill"
        selectedMCPServerIds = Set(workflow.mcpServerIds ?? [])
      }
    }
  }

  private func labeledTextField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(label)
        .font(.appFont(size: 11, weight: .bold))
        .foregroundColor(theme.secondaryTextColor)
      TextField("", text: text)
        .placeholder(when: text.wrappedValue.isEmpty) {
          Text(placeholder).foregroundColor(theme.secondaryTextColor)
        }
        .textFieldStyle(.plain)
        .font(.appFont(size: 14))
        .foregroundColor(theme.textColor)
        .padding(12)
        .background(theme.textColor.opacity(0.05))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.borderColor, lineWidth: 0.5))
    }
  }

  private func toggleMCPServer(_ id: String) {
    if selectedMCPServerIds.contains(id) {
      selectedMCPServerIds.remove(id)
    } else {
      selectedMCPServerIds.insert(id)
    }
  }

  private func saveWorkflow() {
    let ids = Array(selectedMCPServerIds).sorted()
    if let editingWorkflow {
      wsManager.updateWorkflow(
        actionId: editingWorkflow.id,
        name: name,
        prompt: prompt,
        systemImage: systemImage,
        shortcut: nil,
        enabled: true,
        position: nil,
        mcpServerIds: ids,
        inputPolicy: "none",
        executionMode: "run_immediately"
      )
    } else {
      wsManager.addWorkflow(
        name: name,
        prompt: prompt,
        systemImage: systemImage,
        shortcut: nil,
        mcpServerIds: ids,
        inputPolicy: "none",
        executionMode: "run_immediately"
      )
    }
    onDismiss()
  }
}

#Preview {
  WorkflowsSettingsView(wsManager: WebSocketManager())
}
