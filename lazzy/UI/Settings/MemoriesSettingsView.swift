//
//  MemoriesSettingsView.swift
//  lazzy
//
//  Memory management screen for viewing, adding, editing, and deleting AI memories
//

import SwiftUI

struct MemoriesSettingsView: View {
  @ObservedObject var wsManager: WebSocketManager
  @ObservedObject private var theme = ThemeManager.shared

  @State private var memories: [Memory] = []
  @State private var isLoading = false
  @State private var selectedMemory: Memory? = nil
  @State private var newMemoryContent = ""
  @State private var newMemoryCategory = "general"
  @State private var isSavingNew = false
  @FocusState private var isFieldFocused: Bool
  @State private var searchText = ""

  var filteredMemories: [Memory] {
    if searchText.isEmpty {
      return memories
    }
    return memories.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Header
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("AI Memories")
            // .font(.appFont(size: 20, weight: .bold))
            .font(.custom("Sick-Regular", size: 24))
            .foregroundColor(theme.textColor)

          Text("Information the AI remembers about you.")
            .font(.appFont(size: 12))
            .foregroundColor(theme.secondaryTextColor)
        }

        Spacer()

      }

      // Inline Add Memory Form
      VStack(alignment: .leading, spacing: 10) {
        ZStack(alignment: .topLeading) {
          if newMemoryContent.isEmpty {
            Text("Add something simple the AI should remember about you...")
              .font(.appFont(size: 13))
              .foregroundColor(theme.secondaryTextColor.opacity(0.6))
              .padding(.horizontal, 12)
              .padding(.vertical, 10)
              .allowsHitTesting(false)
          }

          TextEditor(text: $newMemoryContent)
            .font(.appFont(size: 13))
            .foregroundColor(theme.textColor)
            .focused($isFieldFocused)
            .padding(8)
            .frame(height: 70)
            .background(theme.inputBackgroundColor.opacity(0.3))
            .cornerRadius(theme.borderRadius / 2)
            .scrollContentBackground(.hidden)
            .overlay(
              RoundedRectangle(cornerRadius: theme.borderRadius / 2)
                .stroke(theme.borderColor.opacity(0.5), lineWidth: 1)
            )
        }

        HStack {
          CustomMenu(
            options: ["General", "Preference", "Fact", "Context", "Instruction"],
            selectedOption: Binding(
              get: { newMemoryCategory.capitalized },
              set: { newMemoryCategory = $0.lowercased() }
            )
          )
          .frame(width: 130)

          Spacer()

          Button(action: saveNewMemory) {
            if isSavingNew {
              ProgressView().scaleEffect(0.6)
            } else {
              HStack(spacing: 4) {
                Image(systemName: "plus")
                Text("Add Memory")
              }
            }
          }
          .buttonStyle(.plain)
          .foregroundColor(theme.backgroundColor)
          .padding(.horizontal, 14)
          .padding(.vertical, 7)
          .background(newMemoryContent.isEmpty ? theme.accentColor.opacity(0.5) : theme.accentColor)
          .cornerRadius(theme.borderRadius / 2)
          .disabled(newMemoryContent.isEmpty || isSavingNew)
        }
      }
      .padding(2)
      // .background(theme.inputBackgroundColor.opacity(0.1))
      // .cornerRadius(theme.borderRadius)
      // .overlay(
      //   RoundedRectangle(cornerRadius: theme.borderRadius)
      //     .stroke(theme.borderColor.opacity(0.3), lineWidth: 1)
      // )

      Divider()
        .padding(.vertical, 4)

      // Search Bar
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
          .font(.appFont(size: 13))
          .foregroundColor(theme.secondaryTextColor)

        TextField("", text: $searchText)
          .placeholder(when: searchText.isEmpty) {
            Text("Search memories...").foregroundColor(theme.secondaryTextColor)
          }
          .textFieldStyle(.plain)
          .font(.appFont(size: 13))
          .foregroundColor(theme.textColor)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(theme.inputBackgroundColor)
      .clipShape(RoundedRectangle(cornerRadius: theme.borderRadius / 1.5))
      .overlay(
        RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
          .stroke(theme.borderColor, lineWidth: 0.5)
      )

      // Memory List
      if isLoading {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if filteredMemories.isEmpty {
        EmptyMemoriesView(onAdd: { isFieldFocused = true })
      } else {
        ScrollView {
          LazyVStack(spacing: 8) {
            ForEach(filteredMemories) { memory in
              MemoryRowView(
                memory: memory,
                onEdit: { selectedMemory = memory },
                onDelete: { deleteMemory(memory) }
              )
            }
          }
        }
      }

      Spacer()

      // Clear All Button
      if !memories.isEmpty {
        HStack {
          Spacer()
          Button(action: clearAllMemories) {
            Text("Clear All Memories")
              .font(.appFont(size: 11))
              .foregroundColor(.red.opacity(0.8))
          }
          .buttonStyle(.plain)
        }
      }
    }
    .onAppear { loadMemories() }
    .sheet(item: $selectedMemory) { memory in
      EditMemorySheet(wsManager: wsManager, memory: memory, onSave: loadMemories)
    }
  }

  private func loadMemories() {
    isLoading = true
    wsManager.listMemories { result in
      isLoading = false
      if let mems = result {
        memories = mems
      }
    }
  }

  private func deleteMemory(_ memory: Memory) {
    wsManager.deleteMemory(id: memory.id) { success in
      if success {
        memories.removeAll { $0.id == memory.id }
      }
    }
  }

  private func clearAllMemories() {
    wsManager.clearMemories { success in
      if success {
        memories = []
      }
    }
  }

  private func saveNewMemory() {
    guard !newMemoryContent.isEmpty else { return }
    isSavingNew = true
    wsManager.addMemory(content: newMemoryContent, category: newMemoryCategory, importance: 5) {
      success in
      isSavingNew = false
      if success {
        newMemoryContent = ""
        loadMemories()
      }
    }
  }
}

// MARK: - Memory Model

struct Memory: Identifiable, Codable {
  let id: String
  let content: String
  let category: String
  let importance: Int
  let source: String?
  let created_at: Int
  let updated_at: Int
}

// MARK: - Memory Row View

struct MemoryRowView: View {
  let memory: Memory
  var onEdit: () -> Void
  var onDelete: () -> Void

  @State private var isHovered = false
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    HStack(spacing: 12) {
      // Category indicator
      Circle()
        .fill(categoryColor)
        .frame(width: 8, height: 8)

      VStack(alignment: .leading, spacing: 4) {
        Text(memory.content)
          .font(.appFont(size: 13))
          .foregroundColor(theme.textColor)
          .lineLimit(2)

        HStack(spacing: 8) {
          Text(memory.category.capitalized)
            .font(.appFont(size: 10, weight: .medium))
            .foregroundColor(theme.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(theme.accentColor.opacity(0.1))
            .cornerRadius(4)

          Text(formatDate(memory.created_at))
            .font(.appFont(size: 10))
            .foregroundColor(theme.secondaryTextColor)
        }
      }

      Spacer()

      if isHovered {
        HStack(spacing: 8) {
          Button(action: onEdit) {
            Image(systemName: "pencil")
              .font(.appFont(size: 12))
              .foregroundColor(theme.accentColor)
          }
          .buttonStyle(.plain)

          Button(action: onDelete) {
            Image(systemName: "trash")
              .font(.appFont(size: 12))
              .foregroundColor(.red.opacity(0.7))
          }
          .buttonStyle(.plain)
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: theme.borderRadius / 2)
        .fill(isHovered ? theme.textColor.opacity(0.05) : Color.clear)
    )
    .onHover { isHovered = $0 }
  }

  private var categoryColor: Color {
    switch memory.category.lowercased() {
    case "preference": return .blue
    case "fact": return .green
    case "context": return .orange
    case "instruction": return .purple
    default: return .gray
    }
  }

  private func formatDate(_ timestamp: Int) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
  }
}

// MARK: - Empty State

struct EmptyMemoriesView: View {
  var onAdd: () -> Void
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "brain.head.profile")
        .font(.appFont(size: 40))
        .foregroundColor(theme.textColor.opacity(0.3))

      Text("No memories yet")
        .font(.appFont(size: 16, weight: .medium))
        .foregroundColor(theme.textColor.opacity(0.6))

      Text("The AI will learn about you as you chat,\nor you can add memories manually.")
        .font(.appFont(size: 12))
        .foregroundColor(theme.secondaryTextColor)
        .multilineTextAlignment(.center)

      Button(action: onAdd) {
        Text("Add Your First Memory")
          .font(.appFont(size: 12, weight: .medium))
          .foregroundColor(theme.accentColor)
      }
      .buttonStyle(.plain)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - Edit Memory Sheet

struct EditMemorySheet: View {
  @ObservedObject var wsManager: WebSocketManager
  let memory: Memory
  var onSave: () -> Void

  @Environment(\.dismiss) var dismiss
  @ObservedObject private var theme = ThemeManager.shared

  @State private var content: String
  @State private var category: String
  @State private var isSaving = false

  private let categories = ["general", "preference", "fact", "context", "instruction"]

  init(wsManager: WebSocketManager, memory: Memory, onSave: @escaping () -> Void) {
    self.wsManager = wsManager
    self.memory = memory
    self.onSave = onSave
    _content = State(initialValue: memory.content)
    _category = State(initialValue: memory.category)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Edit Memory")
        .font(.appFont(size: 18, weight: .bold))
        .foregroundColor(theme.textColor)

      // Content
      VStack(alignment: .leading, spacing: 6) {
        Text("CONTENT")
          .font(.appFont(size: 10, weight: .bold))
          .foregroundColor(theme.secondaryTextColor)

        TextEditor(text: $content)
          .font(.appFont(size: 13))
          .foregroundColor(theme.textColor)
          .padding(8)
          .frame(height: 80)
          .background(theme.inputBackgroundColor)
          .cornerRadius(theme.borderRadius / 2)
          .scrollContentBackground(.hidden)
      }

      // Category
      HStack {
        Text("CATEGORY")
          .font(.appFont(size: 10, weight: .bold))
          .foregroundColor(theme.secondaryTextColor)

        Picker("", selection: $category) {
          ForEach(categories, id: \.self) { cat in
            Text(cat.capitalized).tag(cat)
          }
        }
        .pickerStyle(.menu)
        .frame(width: 120)
      }

      // Actions
      HStack {
        Spacer()

        Button("Cancel") { dismiss() }
          .buttonStyle(.plain)
          .foregroundColor(theme.secondaryTextColor)

        Button(action: updateMemory) {
          if isSaving {
            ProgressView()
              .scaleEffect(0.7)
          } else {
            Text("Update")
          }
        }
        .buttonStyle(.plain)
        .foregroundColor(theme.backgroundColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(theme.accentColor)
        .cornerRadius(theme.borderRadius / 2)
        .disabled(content.isEmpty || isSaving)
      }
    }
    .padding(20)
    .frame(width: 400)
    .background(theme.backgroundColor)
  }

  private func updateMemory() {
    isSaving = true
    wsManager.updateMemory(id: memory.id, content: content, category: category) { success in
      isSaving = false
      if success {
        onSave()
        dismiss()
      }
    }
  }
}

// MARK: - Preview

#Preview {
  MemoriesSettingsView(wsManager: WebSocketManager())
    .padding()
    .frame(width: 500, height: 600)
    .background(Color(white: 0.1))
}
