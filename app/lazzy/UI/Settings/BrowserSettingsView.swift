//
//  BrowserSettingsView.swift
//  lazzy
//
//  Chooses between the signed-in extension and Detach's isolated CDP actor.
//

import SwiftUI

struct BrowserSettingsView: View {
  @ObservedObject var wsManager: WebSocketManager
  @ObservedObject private var theme = ThemeManager.shared

  @AppStorage("browser_automation_mode") private var modeRawValue = BrowserSettings.defaultMode
  @AppStorage("browser_cdp_url") private var cdpUrl = BrowserSettings.defaultCdpUrl
  @AppStorage("browser_headless") private var headless = BrowserSettings.defaultHeadless
  @AppStorage("browser_viewport_width") private var viewportWidth = BrowserSettings.defaultViewportWidth
  @AppStorage("browser_viewport_height") private var viewportHeight = BrowserSettings.defaultViewportHeight
  @AppStorage("browser_user_data_dir") private var userDataDir = BrowserSettings.defaultUserDataDir

  @State private var showAdvanced = false

  private var selectedMode: BrowserAutomationMode {
    get { BrowserAutomationMode(rawValue: modeRawValue) ?? .signedIn }
    nonmutating set {
      modeRawValue = newValue.rawValue
      syncSettings(mode: newValue)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      header

      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          modeSection

          if selectedMode == .signedIn {
            signedInSection
          } else {
            powerSection
          }

          sharedCapabilitiesSection
          Spacer(minLength: 40)
        }
      }
    }
  }

  private var header: some View {
    SettingsPageHeader(
      title: "Browser automation",
      subtitle: "Choose whether Detach works in your signed-in Chrome or a separate browser built for deeper automation."
    )
  }

  private var modeSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionLabel("BROWSER MODE")

      ForEach(BrowserAutomationMode.allCases) { mode in
        Button {
          selectedMode = mode
        } label: {
          HStack(spacing: 12) {
            Image(systemName: mode == .signedIn ? "person.crop.circle.badge.checkmark" : "bolt.shield.fill")
              .font(.system(size: 18, weight: .medium))
              .foregroundColor(selectedMode == mode ? theme.accentColor : theme.secondaryTextColor)
              .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
              HStack(spacing: 7) {
                Text(mode.title)
                  .font(.appFont(size: 13, weight: .semibold))
                  .foregroundColor(theme.textColor)

                if mode == .power {
                  Text("MORE POWERFUL")
                    .font(.appFont(size: 8, weight: .bold))
                    .foregroundColor(theme.backgroundColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(theme.accentColor)
                    .clipShape(Capsule())
                }
              }

              Text(mode.subtitle)
                .font(.appFont(size: 11))
                .foregroundColor(theme.secondaryTextColor.opacity(0.85))
                .multilineTextAlignment(.leading)
            }

            Spacer()

            Image(systemName: selectedMode == mode ? "checkmark.circle.fill" : "circle")
              .foregroundColor(selectedMode == mode ? theme.accentColor : theme.borderColor)
          }
          .padding(14)
          .background(selectedMode == mode ? theme.accentColor.opacity(0.08) : theme.inputBackgroundColor)
          .overlay(
            RoundedRectangle(cornerRadius: theme.borderRadius)
              .stroke(selectedMode == mode ? theme.accentColor.opacity(0.7) : theme.borderColor, lineWidth: selectedMode == mode ? 1 : 0.5)
          )
          .clipShape(RoundedRectangle(cornerRadius: theme.borderRadius))
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var signedInSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      sectionLabel("SIGNED-IN CHROME")

      infoRow(
        icon: "person.text.rectangle",
        title: "Uses your current Chrome profile",
        detail: "Detach can work with sites where you are already logged in. The Detach Browser Agent extension must be connected and allowed on the site."
      )

      infoRow(
        icon: "rectangle.on.rectangle",
        title: "Each task gets its own window",
        detail: "Tabs are isolated for the task and cleaned up when it finishes, while your normal Chrome windows stay untouched."
      )

      HStack(spacing: 7) {
        Circle()
          .fill(wsManager.isConnected ? Color.green : Color.orange)
          .frame(width: 7, height: 7)
        Text(wsManager.isConnected ? "Detach runtime connected" : "Start Detach to connect the browser extension")
          .font(.appFont(size: 11, weight: .medium))
          .foregroundColor(theme.secondaryTextColor)
      }
      .padding(.top, 2)
    }
  }

  private var powerSection: some View {
    VStack(alignment: .leading, spacing: 18) {
      sectionLabel("POWER BROWSER")

      infoRow(
        icon: "lock.shield",
        title: "Separate, persistent profile",
        detail: "Detach keeps a dedicated Chrome profile so normal cookies, cache, and site history can warm up over time. Every task still gets isolated tabs that are closed when it finishes."
      )

      infoRow(
        icon: "cursorarrow.motionlines",
        title: "Deeper browser control",
        detail: "Uses page structure, accessibility data, frames, shadow content, trusted input, reliable loading checks, and direct screenshots."
      )

      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Run in background")
            .font(.appFont(size: 13, weight: .medium))
            .foregroundColor(theme.textColor)
          Text("Faster and less distracting, but the browser window is hidden")
            .font(.appFont(size: 11))
            .foregroundColor(theme.secondaryTextColor.opacity(0.8))
        }
        Spacer()
        Toggle("", isOn: $headless)
          .labelsHidden()
          .toggleStyle(.switch)
          .tint(theme.accentColor)
          .onChange(of: headless) { syncSettings() }
      }

      DisclosureGroup(isExpanded: $showAdvanced) {
        VStack(alignment: .leading, spacing: 14) {
          viewportEditor

          VStack(alignment: .leading, spacing: 6) {
            Text("Existing debugging connection")
              .font(.appFont(size: 12, weight: .medium))
              .foregroundColor(theme.textColor)
            TextField("Optional CDP WebSocket URL", text: $cdpUrl)
              .browserTextField(theme: theme)
              .onChange(of: cdpUrl) { syncSettings() }
            Text("Leave empty so Detach launches and manages the Power browser for you.")
              .font(.appFont(size: 10))
              .foregroundColor(theme.secondaryTextColor.opacity(0.7))
          }

          VStack(alignment: .leading, spacing: 6) {
            Text("Power browser profile folder")
              .font(.appFont(size: 12, weight: .medium))
              .foregroundColor(theme.textColor)
            TextField("Optional custom profile folder", text: $userDataDir)
              .browserTextField(theme: theme)
              .onChange(of: userDataDir) { syncSettings() }
            Text("Leave empty to use Detach’s persistent automation profile. This profile is separate from your everyday Chrome profile.")
              .font(.appFont(size: 10))
              .foregroundColor(theme.secondaryTextColor.opacity(0.7))
          }
        }
        .padding(.top, 12)
      } label: {
        Text("Advanced")
          .font(.appFont(size: 12, weight: .medium))
          .foregroundColor(theme.secondaryTextColor)
      }
      .tint(theme.secondaryTextColor)
    }
  }

  private var viewportEditor: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("Browser size")
        .font(.appFont(size: 12, weight: .medium))
        .foregroundColor(theme.textColor)

      HStack(spacing: 8) {
        TextField("1280", value: $viewportWidth, format: .number)
          .browserTextField(theme: theme)
          .frame(width: 72)
          .onChange(of: viewportWidth) { syncSettings() }
        Text("×")
          .foregroundColor(theme.secondaryTextColor)
        TextField("720", value: $viewportHeight, format: .number)
          .browserTextField(theme: theme)
          .frame(width: 72)
          .onChange(of: viewportHeight) { syncSettings() }
        Text("pixels")
          .font(.appFont(size: 11))
          .foregroundColor(theme.secondaryTextColor)
      }
    }
  }

  private var sharedCapabilitiesSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionLabel("AVAILABLE IN BOTH MODES")
      capability("checkmark.circle", "Verified clicks, typing, keys, dropdowns, and file uploads")
      capability("clock.badge.checkmark", "Page-readiness waits and action completion checks")
      capability("number.square", "Stable page element references with fewer repeated inspections")
      capability("rectangle.stack", "Task-scoped tabs, cleanup, screenshots, and detailed traces")
    }
  }

  private func sectionLabel(_ text: String) -> some View {
    SettingsSectionHeader(title: text.capitalized)
  }

  private func infoRow(icon: String, title: String, detail: String) -> some View {
    HStack(alignment: .top, spacing: 11) {
      Image(systemName: icon)
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(theme.accentColor)
        .frame(width: 20)
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.appFont(size: 13, weight: .medium))
          .foregroundColor(theme.textColor)
        Text(detail)
          .font(.appFont(size: 11))
          .lineSpacing(3)
          .foregroundColor(theme.secondaryTextColor.opacity(0.82))
      }
    }
  }

  private func capability(_ icon: String, _ text: String) -> some View {
    HStack(spacing: 9) {
      Image(systemName: icon)
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(theme.accentColor)
        .frame(width: 16)
      Text(text)
        .font(.appFont(size: 12))
        .foregroundColor(theme.secondaryTextColor)
    }
  }

  private func syncSettings(mode: BrowserAutomationMode? = nil) {
    wsManager.updateBrowserSettings(
      mode: (mode ?? selectedMode).rawValue,
      cdpUrl: cdpUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : cdpUrl,
      headless: headless,
      viewportWidth: max(800, min(3840, viewportWidth)),
      viewportHeight: max(600, min(2160, viewportHeight)),
      userDataDir: userDataDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : userDataDir
    )
  }
}

private extension View {
  func browserTextField(theme: ThemeManager) -> some View {
    self
      .font(.appFont(size: 12, design: .monospaced))
      .foregroundColor(theme.textColor)
      .textFieldStyle(.plain)
      .padding(8)
      .background(theme.inputBackgroundColor)
      .clipShape(RoundedRectangle(cornerRadius: theme.borderRadius / 1.5))
      .overlay(
        RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
          .stroke(theme.borderColor, lineWidth: 0.5)
      )
  }
}

#Preview {
  BrowserSettingsView(wsManager: WebSocketManager())
    .padding()
    .frame(width: 520, height: 760)
    .background(Color(white: 0.1))
}
