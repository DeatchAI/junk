import SwiftUI
import UniformTypeIdentifiers

struct SecretsSettingsView: View {
  @ObservedObject private var vault = SecretVault.shared
  @State private var label = ""
  @State private var username = ""
  @State private var password = ""
  @State private var origin = "https://"
  @State private var status = ""
  @State private var showsApplePasswordsImport = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text("Secrets")
          .font(.appFont(size: 20, weight: .semibold))

        Text("Credentials stay in your Mac’s Keychain. Agents can search labels and request Touch ID, but never read a password, token, or account value.")
          .font(.appFont(size: 12))
          .foregroundStyle(.secondary)

        HStack(spacing: 10) {
          Button("Import from Apple Passwords") { showsApplePasswordsImport = true }
            .buttonStyle(.borderedProminent)
          Text(status)
            .font(.appFont(size: 11))
            .foregroundStyle(.secondary)
        }

        GroupBox("Add credential") {
          VStack(spacing: 10) {
            TextField("Label, e.g. GitHub Work", text: $label)
            TextField("Username or email", text: $username)
            SecureField("Password", text: $password)
            TextField("Exact origin, e.g. https://github.com", text: $origin)
            HStack {
              Spacer()
              Button("Save securely") { save() }
                .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || origin == "https://")
            }
          }
          .textFieldStyle(.roundedBorder)
          .padding(.top, 6)
        }

        if vault.credentials.isEmpty {
          Text("No saved credentials yet.").foregroundStyle(.secondary)
        } else {
          ForEach(vault.credentials) { credential in
            HStack {
              Image(systemName: "lock.fill").foregroundStyle(.green)
              VStack(alignment: .leading) {
                Text(credential.label).font(.appFont(size: 12, weight: .semibold))
                Text("\(credential.maskedUsername) · \(credential.origin)").font(.appFont(size: 10)).foregroundStyle(.secondary)
              }
              Spacer()
              Button(role: .destructive) { vault.remove(credential) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 4)
          }
        }
      }
      .padding(.vertical, 4)
    }
    .sheet(isPresented: $showsApplePasswordsImport) {
      ApplePasswordsImportSheet(vault: vault) { message in
        status = message
      }
    }
  }

  private func save() {
    do {
      try vault.add(label: label, username: username, password: password, origin: origin)
      label = ""; username = ""; password = ""; origin = "https://"
      status = "Saved in Keychain. Touch ID is required before every agent use."
    } catch { status = error.localizedDescription }
  }
}

private struct ApplePasswordsImportSheet: View {
  @ObservedObject var vault: SecretVault
  let onFinished: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var showsFileImporter = false
  @State private var dropTargeted = false
  @State private var preview: SecretCSVImportPreview?
  @State private var sourceURL: URL?
  @State private var status = ""
  @State private var moveExportToTrash = true

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        Text("Apple Passwords")
          .font(.appFont(size: 20, weight: .semibold))
        Spacer()
        Button { cancel() } label: { Image(systemName: "xmark.circle.fill") }
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Instructions").font(.appFont(size: 14, weight: .semibold))
        Text("1. Open the Passwords app on your Mac.\n2. Choose File → Export Passwords.\n3. Confirm, then save the CSV file.")
          .font(.appFont(size: 13))
          .foregroundStyle(.secondary)
          .padding(14)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
      }

      if let preview {
        previewView(preview)
      } else {
        dropZone
      }

      if !status.isEmpty {
        Text(status).font(.appFont(size: 11)).foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)
      HStack {
        Toggle("Move exported CSV to Trash after import", isOn: $moveExportToTrash)
          .font(.appFont(size: 11))
        Spacer()
        Button("Cancel") { cancel() }
        Button("Import") { commit() }
          .buttonStyle(.borderedProminent)
          .disabled(preview == nil || preview?.importableCount == 0)
      }
    }
    .padding(28)
    .frame(width: 540, height: 510)
    .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
      if case .success(let url) = result { load(url) }
      if case .failure(let error) = result { status = error.localizedDescription }
    }
  }

  private var dropZone: some View {
    Button { showsFileImporter = true } label: {
      VStack(spacing: 10) {
        Image(systemName: "doc.badge.plus")
          .font(.system(size: 30))
        Text("Drop your CSV here or click to browse")
          .font(.appFont(size: 13, weight: .medium))
      }
      .foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary)
      .frame(maxWidth: .infinity, minHeight: 132)
      .background(dropTargeted ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 14))
      .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4])).foregroundStyle(.secondary.opacity(0.45)))
    }
    .buttonStyle(.plain)
    .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted, perform: acceptDrop)
  }

  private func previewView(_ preview: SecretCSVImportPreview) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Image(systemName: "doc.text.fill").foregroundStyle(.green)
        VStack(alignment: .leading, spacing: 2) {
          Text(preview.fileName).font(.appFont(size: 13, weight: .semibold))
          Text("Found \(preview.importableCount) credential\(preview.importableCount == 1 ? "" : "s") ready to import")
            .font(.appFont(size: 11)).foregroundStyle(.secondary)
        }
        Spacer()
        Button("Choose another") { showsFileImporter = true }.font(.appFont(size: 11))
      }
      if preview.duplicateCount > 0 || preview.skippedCount > 0 {
        Text("\(preview.duplicateCount) duplicate\(preview.duplicateCount == 1 ? "" : "s") skipped · \(preview.skippedCount) invalid or unsupported row\(preview.skippedCount == 1 ? "" : "s") skipped")
          .font(.appFont(size: 11)).foregroundStyle(.secondary)
      }
      if !preview.sampleLabels.isEmpty {
        Text(preview.sampleLabels.joined(separator: " · "))
          .font(.appFont(size: 11)).foregroundStyle(.secondary).lineLimit(1)
      }
    }
    .padding(16)
    .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
  }

  private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
    guard let provider = providers.first else { return false }
    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
      let url: URL?
      if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
      else { url = item as? URL }
      if let url { DispatchQueue.main.async { load(url) } }
    }
    return true
  }

  private func load(_ url: URL) {
    vault.discardImport(preview)
    do {
      preview = try vault.previewApplePasswordsCSV(at: url)
      sourceURL = url
      status = ""
    } catch { status = error.localizedDescription }
  }

  private func commit() {
    guard let preview else { return }
    do {
      let result = try vault.commitImport(preview)
      if moveExportToTrash, let sourceURL {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
        try? FileManager.default.trashItem(at: sourceURL, resultingItemURL: nil)
      }
      onFinished("Imported \(result.importedCount) credential\(result.importedCount == 1 ? "" : "s") securely.")
      dismiss()
    } catch { status = error.localizedDescription }
  }

  private func cancel() {
    vault.discardImport(preview)
    dismiss()
  }
}
