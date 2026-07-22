import SwiftUI
import UniformTypeIdentifiers

struct SecretsSettingsView: View {
  @ObservedObject private var vault = SecretVault.shared
  @ObservedObject private var audit = SecretAccessAudit.shared
  @ObservedObject private var theme = ThemeManager.shared
  @State private var label = ""
  @State private var username = ""
  @State private var password = ""
  @State private var origin = "https://"
  @State private var status = ""
  @State private var showsApplePasswordsImport = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        HStack(alignment: .bottom, spacing: 20) {
          SettingsPageHeader(
            title: "Secrets",
            subtitle: "Credentials stay in Keychain. Agents can request a secure fill after Touch ID, but never read the value."
          )

          Spacer()

          Button { showsApplePasswordsImport = true } label: {
            Label("Import", systemImage: "square.and.arrow.down")
              .font(.appFont(size: 11, weight: .semibold))
              .foregroundColor(theme.backgroundColor)
              .padding(.horizontal, 12)
              .padding(.vertical, 7)
              .background(theme.accentColor)
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          }
          .buttonStyle(.plain)
        }

        if !status.isEmpty {
          HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundColor(.green)
            Text(status)
              .font(.appFont(size: 10.5))
              .foregroundColor(theme.secondaryTextColor)
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 9)
          .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }

        VStack(alignment: .leading, spacing: 10) {
          SettingsSectionHeader(
            title: "Add credential",
            subtitle: "Use the exact website origin so Detach only offers the credential in the right place."
          )

          SettingsCard {
            VStack(spacing: 9) {
              TextField("Label, e.g. GitHub Work", text: $label)
                .secretTextField(theme: theme)
              TextField("Username or email", text: $username)
                .secretTextField(theme: theme)
              SecureField("Password", text: $password)
                .secretTextField(theme: theme)
              TextField("Exact origin, e.g. https://github.com", text: $origin)
                .secretTextField(theme: theme)

              HStack {
                Text("Touch ID is required before every agent use.")
                  .font(.appFont(size: 10))
                  .foregroundColor(theme.secondaryTextColor)
                Spacer()
                Button("Save securely") { save() }
                  .font(.appFont(size: 11, weight: .semibold))
                  .buttonStyle(.borderedProminent)
                  .tint(theme.accentColor)
                  .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || origin == "https://")
              }
              .padding(.top, 2)
            }
            .padding(14)
          }
        }

        VStack(alignment: .leading, spacing: 10) {
          SettingsSectionHeader(title: "Saved credentials")

          SettingsCard {
            if vault.credentials.isEmpty {
              HStack(spacing: 10) {
                Image(systemName: "key.horizontal")
                  .foregroundColor(theme.secondaryTextColor)
                Text("No saved credentials yet")
                  .font(.appFont(size: 11.5))
                  .foregroundColor(theme.secondaryTextColor)
                Spacer()
              }
              .padding(16)
            } else {
              ForEach(Array(vault.credentials.enumerated()), id: \.element.id) { index, credential in
                HStack(spacing: 10) {
                  SecretSiteIcon(origin: credential.origin, size: 28)
                  VStack(alignment: .leading, spacing: 3) {
                    Text(credential.label)
                      .font(.appFont(size: 12, weight: .semibold))
                      .foregroundColor(theme.textColor)
                    Text("\(credential.maskedUsername) · \(displayHost(for: credential.origin))")
                      .font(.appFont(size: 10))
                      .foregroundColor(theme.secondaryTextColor)
                  }
                  Spacer()
                  SettingsIconButton(icon: "trash", accessibilityLabel: "Delete \(credential.label)", tint: .red) {
                    vault.remove(credential)
                  }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)

                if index < vault.credentials.count - 1 {
                  SettingsCardDivider()
                }
              }
            }
          }
        }

        VStack(alignment: .leading, spacing: 10) {
          SettingsSectionHeader(
            title: "Access history",
            subtitle: "Encrypted on this Mac. Credential values are never written to this log."
          )

          SettingsCard {
            if audit.records.isEmpty {
              HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                  .foregroundColor(theme.secondaryTextColor)
                Text("No credential use has been recorded")
                  .font(.appFont(size: 11.5))
                  .foregroundColor(theme.secondaryTextColor)
                Spacer()
              }
              .padding(16)
            } else {
              VStack(spacing: 0) {
                AccessHistoryTableHeader()

                ForEach(Array(audit.records.enumerated()), id: \.element.id) { index, record in
                  AccessHistoryTableRow(record: record)

                  if index < audit.records.count - 1 {
                    SettingsCardDivider()
                  }
                }
              }
            }
          }
        }

        Spacer(minLength: 20)
      }
      .padding(.bottom, 24)
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

  private func displayHost(for origin: String) -> String {
    URL(string: origin)?.host(percentEncoded: false) ?? origin
  }
}

private struct AccessHistoryTableHeader: View {
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    HStack(spacing: 16) {
      tableHeader("Website/App")
        .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
      tableHeader("Activity")
        .frame(width: 122, alignment: .leading)
      tableHeader("When")
        .frame(width: 192, alignment: .leading)
      tableHeader("Status")
        .frame(width: 28, alignment: .center)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    // .background(theme.textColor.opacity(0.04))
  }

  private func tableHeader(_ title: String) -> some View {
    Text(title.uppercased())
      .font(.appFont(size: 9.5, weight: .semibold))
      .foregroundColor(theme.secondaryTextColor)
      .tracking(0.45)
  }
}

private struct AccessHistoryTableRow: View {
  let record: SecretAccessRecord
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    HStack(spacing: 16) {
      HStack(spacing: 9) {
        SecretSiteIcon(origin: record.origin, size: 28)
        VStack(alignment: .leading, spacing: 2) {
          Text(host)
            .font(.appFont(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(theme.textColor)
            .lineLimit(1)
          // Text(record.credentialLabel)
          //   .font(.appFont(size: 9.5))
          //   .foregroundColor(theme.secondaryTextColor)
          //   .lineLimit(1)
        }
      }
      .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)

      Text(record.action)
        .font(.appFont(size: 11, weight: .medium, design: .monospaced))
        .foregroundColor(theme.secondaryTextColor)
        .lineLimit(1)
        .frame(width: 122, alignment: .leading)

      Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
        .font(.appFont(size: 11, weight: .medium, design: .monospaced))
        .foregroundColor(theme.secondaryTextColor)
        .lineLimit(1)
        .frame(width: 192, alignment: .leading)

      Image(systemName: outcomeIcon)
        .font(.appFont(size: 12, weight: .semibold))
        .foregroundStyle(outcomeColor)
        .frame(width: 28, alignment: .center)
        .accessibilityLabel(record.outcome.title)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
  }

  private var host: String {
    URL(string: record.origin)?.host(percentEncoded: false) ?? record.origin
  }

  private var outcomeIcon: String {
    switch record.outcome {
    case .used: return "checkmark.circle.fill"
    case .denied: return "hand.raised.fill"
    case .failed: return "exclamationmark.circle.fill"
    }
  }

  private var outcomeColor: Color {
    switch record.outcome {
    case .used: return .green
    case .denied: return .orange
    case .failed: return .red
    }
  }
}

/// Displays a site favicon when it is available, while keeping a local hostname
/// monogram as the reliable fallback for offline, private, or custom origins.
private struct SecretSiteIcon: View {
  let origin: String
  let size: CGFloat
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    Group {
      if let faviconURL {
        AsyncImage(url: faviconURL, transaction: Transaction(animation: .easeInOut(duration: 0.15))) { phase in
          if case let .success(image) = phase {
            image
              .resizable()
              .aspectRatio(contentMode: .fit)
              .padding(5)
          } else {
            fallback
          }
        }
      } else {
        fallback
      }
    }
    .frame(width: size, height: size)
    .background(theme.inputBackgroundColor)
    .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        .stroke(theme.textColor.opacity(0.08), lineWidth: 0.7)
    )
    .accessibilityHidden(true)
  }

  private var faviconURL: URL? {
    guard let components = URLComponents(string: origin),
          let host = components.host,
          !host.isEmpty else { return nil }
    var faviconComponents = URLComponents()
    faviconComponents.scheme = components.scheme == "http" ? "http" : "https"
    faviconComponents.host = host
    faviconComponents.path = "/favicon.ico"
    return faviconComponents.url
  }

  private var fallback: some View {
    Text(hostInitial)
      .font(.appFont(size: size * 0.42, weight: .semibold))
      .foregroundColor(theme.accentColor)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var hostInitial: String {
    let host = URL(string: origin)?.host(percentEncoded: false) ?? origin
    return host.first.map { String($0).uppercased() } ?? "•"
  }
}

private extension View {
  func secretTextField(theme: ThemeManager) -> some View {
    self
      .font(.appFont(size: 11.5))
      .foregroundColor(theme.textColor)
      .textFieldStyle(.plain)
      .padding(.horizontal, 11)
      .padding(.vertical, 9)
      .background(theme.inputBackgroundColor)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(theme.textColor.opacity(0.09), lineWidth: 0.7)
      )
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
