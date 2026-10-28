import AppKit
import SwiftUI

struct BrowserExtensionOnboardingView: View {
  @State private var extensionFolderError: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      instruction("1", "Open Chrome's Extensions page.")
      instruction("2", "Turn on Developer mode, then choose Load unpacked.")
      instruction("3", "Select the Detach Browser Agent folder.")

      HStack(spacing: 12) {
        Button("Open Chrome Extensions", action: openChromeExtensions)
          .buttonStyle(OnboardingActionButtonStyle(isPrimary: true))
        Button("Show extension folder", action: showExtensionFolder)
          .buttonStyle(OnboardingActionButtonStyle(isPrimary: false))
      }
      .frame(maxWidth: .infinity)
      .padding(.top, 4)

      if let extensionFolderError {
        Text(extensionFolderError)
          .font(OnboardingWelcomeFonts.inter(size: 12))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
      }
    }
    .padding(20)
    // .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    // .overlay {
    //   RoundedRectangle(cornerRadius: 16, style: .continuous)
    //     .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    // }
    .onAppear(perform: prepareExtensionFolder)
  }

  private func instruction(_ number: String, _ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 13) {
      Text(number)
        .font(OnboardingWelcomeFonts.inter(size: 12))
        .foregroundStyle(.secondary)
        .frame(width: 18)
      Text(text)
        .font(OnboardingWelcomeFonts.inter(size: 13))
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
  }

  private func prepareExtensionFolder() {
    do {
      _ = try BrowserExtensionInstaller.prepareForManualSetup()
      extensionFolderError = nil
    } catch {
      extensionFolderError = "The bundled extension folder couldn't be prepared. You can continue setup and try again in Browser settings."
    }
  }

  private func openChromeExtensions() {
    guard let chromeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome"),
      let extensionsURL = URL(string: "chrome://extensions")
    else {
      extensionFolderError = "Google Chrome couldn't be found. Install Chrome to load the bundled extension."
      return
    }

    NSWorkspace.shared.open(
      [extensionsURL],
      withApplicationAt: chromeURL,
      configuration: NSWorkspace.OpenConfiguration()
    ) { _, error in
      DispatchQueue.main.async {
        extensionFolderError = error == nil
          ? nil
          : "Chrome couldn't be opened. Open chrome://extensions and load the bundled folder manually."
      }
    }
  }

  private func showExtensionFolder() {
    do {
      let url = try BrowserExtensionInstaller.prepareForManualSetup()
      NSWorkspace.shared.activateFileViewerSelecting([url])
      extensionFolderError = nil
    } catch {
      extensionFolderError = "The bundled extension folder isn't available in this app build."
    }
  }
}
