//
//  QuickActionsSettingsView.swift
//  lazzy
//
//  Settings view for managing user-created quick actions
//

import SwiftUI

struct QuickActionsSettingsView: View {
  @ObservedObject var wsManager: WebSocketManager
  @ObservedObject private var theme = ThemeManager.shared

  @State private var showAddForm = false
  @State private var editingAction: QuickAction? = nil

  init(wsManager: WebSocketManager, startInCreateMode: Bool = false) {
    self.wsManager = wsManager
    _showAddForm = State(initialValue: startInCreateMode)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      // Header
      VStack(alignment: .leading, spacing: 8) {
        Text("Quick Actions")
          // .font(.appFont(size: 24, weight: .bold))
          .font(.custom("Sick-Regular", size: 24))
          .foregroundColor(theme.textColor)

        Text(
          "Create custom AI actions that appear in your quick actions menu. Each action has a name and a prompt template."
        )
        .font(.appFont(size: 13))
        .foregroundColor(theme.secondaryTextColor)
        .lineSpacing(4)
      }
      .padding(.bottom, 8)

      if showAddForm || editingAction != nil {
        // Add/Edit Form
        QuickActionFormView(
          wsManager: wsManager,
          editingAction: editingAction,
          onDismiss: {
            withAnimation(.easeInOut) {
              showAddForm = false
              editingAction = nil
            }
          }
        )
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
      } else {
        // Main List View
        VStack(alignment: .leading, spacing: 16) {
          // Add button row
          HStack {
            Spacer()
            Button(action: {
              withAnimation(.easeInOut) {
                showAddForm = true
              }
            }) {
              HStack(spacing: 4) {
                Image(systemName: "plus")
                  .font(.appFont(size: 12, weight: .semibold))
                Text("Add Action")
                  .font(.appFont(size: 12, weight: .semibold))
              }
              .foregroundColor(theme.backgroundColor)
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .background(theme.accentColor)
              .cornerRadius(theme.borderRadius / 1.5)
            }
            .buttonStyle(.plain)
          }

          // Actions List
          if wsManager.customQuickActions.isEmpty {
            emptyState
          } else {
            ScrollView {
              VStack(spacing: 12) {
                ForEach(wsManager.customQuickActions) { action in
                  QuickActionRow(
                    action: action,
                    onEdit: {
                      withAnimation(.easeInOut) {
                        editingAction = action
                      }
                    },
                    onDelete: {
                      wsManager.deleteQuickAction(actionId: action.id)
                    }
                  )
                }
              }
            }
          }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
      }
    }
    .onAppear {
      wsManager.listQuickActions()
    }
  }

  private var emptyState: some View {
    VStack(spacing: 16) {
      Image(systemName: "bolt.circle")
        .font(.appFont(size: 48))
        .foregroundColor(theme.secondaryTextColor.opacity(0.5))

      Text("No Quick Actions Yet")
        .font(.appFont(size: 16, weight: .semibold))
        .foregroundColor(theme.secondaryTextColor)

      Text("Create custom AI actions with predefined prompts")
        .font(.appFont(size: 13))
        .foregroundColor(theme.secondaryTextColor.opacity(0.7))
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 60)
  }
}

// MARK: - Quick Action Row

struct QuickActionRow: View {
  let action: QuickAction
  let onEdit: () -> Void
  let onDelete: () -> Void

  @ObservedObject private var theme = ThemeManager.shared
  @State private var isHovered = false
  @State private var showDeleteConfirm = false

  var body: some View {
    HStack(spacing: 12) {
      // Icon
      ZStack {
        RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
          .fill(theme.accentColor.opacity(0.15))
          .frame(width: 40, height: 40)

        Image(systemName: action.systemImage ?? "bolt.fill")
          .font(.appFont(size: 16))
          .foregroundColor(theme.accentColor)
      }

      // Content
      VStack(alignment: .leading, spacing: 4) {
        Text(action.title)
          .font(.appFont(size: 14, weight: .semibold))
          .foregroundColor(theme.textColor)

        if let prompt = action.prompt {
          Text(prompt)
            .font(.appFont(size: 12))
            .foregroundColor(theme.secondaryTextColor)
            .lineLimit(1)
        }

        if let integrations = action.integrations, !integrations.isEmpty {
          HStack(spacing: 4) {
            Image(systemName: "link")
              .font(.appFont(size: 10))
            Text(integrations.joined(separator: ", "))
              .font(.appFont(size: 10))
          }
          .foregroundColor(theme.secondaryTextColor.opacity(0.7))
        }

        if let mcpServerIds = action.mcpServerIds, !mcpServerIds.isEmpty {
          HStack(spacing: 4) {
            Image(systemName: "server.rack")
              .font(.appFont(size: 10))
            Text("\(mcpServerIds.count) MCP capability\(mcpServerIds.count == 1 ? "" : "s")")
              .font(.appFont(size: 10))
          }
          .foregroundColor(theme.secondaryTextColor.opacity(0.7))
        }
      }

      Spacer()

      // Actions (visible on hover)
      if isHovered {
        HStack(spacing: 8) {
          Button(action: onEdit) {
            Image(systemName: "pencil")
              .font(.appFont(size: 12))
              .foregroundColor(theme.textColor)
              .padding(6)
              .background(theme.textColor.opacity(0.1))
              .cornerRadius(theme.borderRadius / 2)
          }
          .buttonStyle(.plain)

          Button(action: { showDeleteConfirm = true }) {
            Image(systemName: "trash")
              .font(.appFont(size: 12))
              .foregroundColor(.red)
              .padding(6)
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
    .alert("Delete Quick Action?", isPresented: $showDeleteConfirm) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive, action: onDelete)
    } message: {
      Text("This action cannot be undone.")
    }
  }
}

// MARK: - Quick Action Form

struct QuickActionFormView: View {
  @ObservedObject var wsManager: WebSocketManager
  let editingAction: QuickAction?
  let onDismiss: () -> Void

  @ObservedObject private var theme = ThemeManager.shared

  @State private var name: String = ""
  @State private var prompt: String = ""
  @State private var systemImage: String = "bolt.fill"
  @State private var selectedMCPServerIds = Set<String>()

  private let availableIcons = [
    "bolt.fill", "doc.text.fill", "globe", "envelope.fill", "calendar",
    "checkmark.circle.fill", "star.fill", "bookmark.fill", "tag.fill",
    "folder.fill", "paperplane.fill", "lightbulb.fill", "wand.and.stars",
    "sparkles", "brain.head.profile", "text.bubble.fill", "list.bullet",
  ]

  var isEditing: Bool { editingAction != nil }

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      // Header with back button
      HStack {
        Text(isEditing ? "Edit Action" : "New Action")
          .font(.appFont(size: 16, weight: .semibold))
          .foregroundColor(theme.textColor)

        Spacer()

        Button(action: onDismiss) {
          HStack(spacing: 4) {
            Image(systemName: "chevron.left")
              .font(.appFont(size: 12, weight: .semibold))
            Text("Back")
              .font(.appFont(size: 13, weight: .medium))
          }
          .foregroundColor(theme.secondaryTextColor)
        }
        .buttonStyle(.plain)
      }

      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          // Name Field
          VStack(alignment: .leading, spacing: 8) {
            Text("NAME")
              .font(.appFont(size: 11, weight: .bold))
              .foregroundColor(theme.secondaryTextColor)

            TextField("", text: $name)
              .placeholder(when: name.isEmpty) {
                Text("e.g., Summarize").foregroundColor(theme.secondaryTextColor)
              }
              .textFieldStyle(.plain)
              .font(.appFont(size: 14))
              .foregroundColor(theme.textColor)
              .padding(12)
              .background(theme.textColor.opacity(0.05))
              .cornerRadius(8)
              .overlay(
                RoundedRectangle(cornerRadius: 8)
                  .stroke(theme.borderColor, lineWidth: 0.5)
              )
          }

          // Prompt Field
          VStack(alignment: .leading, spacing: 8) {
            Text("PROMPT TEMPLATE")
              .font(.appFont(size: 11, weight: .bold))
              .foregroundColor(theme.secondaryTextColor)

            TextEditor(text: $prompt)
              .font(.appFont(size: 13))
              .foregroundColor(theme.textColor)
              .scrollContentBackground(.hidden)
              .frame(minHeight: 100, maxHeight: 150)
              .padding(12)
              .background(theme.textColor.opacity(0.05))
              .cornerRadius(8)
              .overlay(
                RoundedRectangle(cornerRadius: 8)
                  .stroke(theme.borderColor, lineWidth: 0.5)
              )

            Text("This prompt will be sent to the AI when the action is triggered.")
              .font(.appFont(size: 11))
              .foregroundColor(theme.secondaryTextColor.opacity(0.8))
          }

          // Icon Picker
          VStack(alignment: .leading, spacing: 8) {
            Text("ICON")
              .font(.appFont(size: 11, weight: .bold))
              .foregroundColor(theme.secondaryTextColor)

            LazyVGrid(
              columns: Array(repeating: GridItem(.fixed(40), spacing: 8), count: 8), spacing: 8
            ) {
              ForEach(availableIcons, id: \.self) { icon in
                Button(action: { systemImage = icon }) {
                  Image(systemName: icon)
                    .font(.appFont(size: 16))
                    .foregroundColor(systemImage == icon ? theme.backgroundColor : theme.textColor)
                    .frame(width: 40, height: 40)
                    .background(
                      RoundedRectangle(cornerRadius: 8)
                        .fill(
                          systemImage == icon ? theme.accentColor : theme.textColor.opacity(0.05))
                    )
                    .overlay(
                      RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
                        .stroke(
                          systemImage == icon ? theme.accentColor : theme.borderColor,
                          lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
              }
            }
          }

          VStack(alignment: .leading, spacing: 8) {
            Text("MCP CAPABILITIES")
              .font(.appFont(size: 11, weight: .bold))
              .foregroundColor(theme.secondaryTextColor)

            let options = actionMCPOptions(
              from: wsManager.mcpServers,
              composioIntegrations: wsManager.composioIntegrations
            )
            VStack(spacing: 6) {
              ForEach(options) { option in
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

          // Save Button
          HStack {
            Spacer()
            Button(action: saveAction) {
              Text(isEditing ? "Save Changes" : "Create Action")
                .font(.appFont(size: 14, weight: .semibold))
                .foregroundColor(theme.backgroundColor)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                  RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
                    .fill(
                      name.isEmpty || prompt.isEmpty
                        ? theme.accentColor.opacity(0.5) : theme.accentColor)
                )
            }
            .buttonStyle(.plain)
            .disabled(name.isEmpty || prompt.isEmpty)
            Spacer()
          }
          .padding(.top, 8)

          Spacer(minLength: 40)
        }
      }
    }
    .onAppear {
      if let action = editingAction {
        name = action.title
        prompt = action.prompt ?? ""
        systemImage = action.systemImage ?? "bolt.fill"
        selectedMCPServerIds = Set(action.mcpServerIds ?? [])
      }
      wsManager.listMCPServers()
      wsManager.listComposioIntegrations(limit: 100)
    }
  }

  private func toggleMCPServer(_ id: String) {
    if selectedMCPServerIds.contains(id) {
      selectedMCPServerIds.remove(id)
    } else {
      selectedMCPServerIds.insert(id)
    }
  }

  private func saveAction() {
    let mcpServerIds = Array(selectedMCPServerIds).sorted()
    if let editingAction = editingAction {
      // Update existing action
      wsManager.updateQuickAction(
        actionId: editingAction.id,
        name: name,
        prompt: prompt,
        integrations: nil,
        systemImage: systemImage,
        shortcut: nil,
        enabled: true,
        position: nil,
        mcpServerIds: mcpServerIds
      )
    } else {
      // Create new action
      wsManager.addQuickAction(
        name: name,
        prompt: prompt,
        integrations: nil,
        systemImage: systemImage,
        shortcut: nil,
        mcpServerIds: mcpServerIds
      )
    }

    onDismiss()
  }
}

// MARK: - Preview

#Preview {
  QuickActionsSettingsView(wsManager: WebSocketManager())
    .padding()
    .frame(width: 500, height: 600)
    .background(Color(white: 0.1))
}
