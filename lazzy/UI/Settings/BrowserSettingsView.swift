//
//  BrowserSettingsView.swift
//  lazzy
//
//  Browser automation configuration with auto-detect CDP URL feature
//

import AppKit
import SwiftUI

struct BrowserSettingsView: View {
  @ObservedObject var wsManager: WebSocketManager

  // Browser settings state
  @AppStorage("browser_cdp_url") private var cdpUrl = BrowserSettings.defaultCdpUrl
  @AppStorage("browser_headless") private var headless = BrowserSettings.defaultHeadless
  @AppStorage("browser_viewport_width") private var viewportWidth = BrowserSettings
    .defaultViewportWidth
  @AppStorage("browser_viewport_height") private var viewportHeight = BrowserSettings
    .defaultViewportHeight
  @AppStorage("browser_use_daily_driver") private var useDailyDriverProfile = BrowserSettings
    .defaultUseDailyDriverProfile
  @AppStorage("browser_user_data_dir") private var userDataDir = BrowserSettings
    .defaultUserDataDir

  // Theme manager
  @ObservedObject private var theme = ThemeManager.shared

  // Auto-detect state
  @State private var isDetecting = false
  @State private var detectStatus: DetectStatus = .idle
  @State private var launchedChromeProcess: Process?
  @State private var showDailyDriverAlert = false
  @State private var dailyDriverStatus: String?
  @State private var dailyDriverError: String?

  enum DetectStatus: Equatable {
    case idle
    case launching
    case querying
    case success(String)
    case error(String)
  }

  // Available browsers for auto-detect
  private let supportedBrowsers = [
    ("Google Chrome", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
    ("Microsoft Edge", "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"),
    ("Brave Browser", "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"),
    ("Chromium", "/Applications/Chromium.app/Contents/MacOS/Chromium"),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      // Header
      VStack(alignment: .leading, spacing: 8) {
        Text("Browser Automation")
          .font(.custom("Sick-Regular", size: 24))
          .foregroundColor(theme.textColor)

        Text(
          "Configure browser settings for AI-driven web automation. Detach uses Chrome DevTools Protocol (CDP) to control Chromium-based browsers: "
        )
        .font(.appFont(size: 13))
        .lineSpacing(4)
        .foregroundColor(theme.secondaryTextColor)

        VStack(alignment: .leading, spacing: 4) {
          bulletPoint("Works with Chrome, Edge, Brave, and other Chromium browsers")
          bulletPoint("Auto-detect launches a fresh browser with debug port enabled")
          bulletPoint("Manual CDP URL lets you connect to your existing logged-in browser")
          bulletPoint("Sessions persist across AI conversations until closed")
        }
      }
      .padding(.bottom, 8)

      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          // Auto-detect Section
          autoDetectSection

          Divider().opacity(0.1)

          // Manual CDP URL Section
          manualCdpSection

          Divider().opacity(0.1)

          // Browser Options
          browserOptionsSection

          // Divider().opacity(0.1)

          Spacer(minLength: 40)
        }
      }
    }
  }

  // MARK: - Auto-detect Section

  private var autoDetectSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("CONNECT BROWSER")
          .font(.appFont(size: 11, weight: .bold))
          .foregroundColor(theme.secondaryTextColor)

        Spacer()

        if case .success = detectStatus {
          HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundColor(.green)
            Text("Connected")
              .font(.appFont(size: 11))
              .foregroundColor(.green)
          }
        }
      }

      // Daily Driver Option
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Image(systemName: "person.fill")
            .font(.appFont(size: 14))
            .foregroundColor(theme.accentColor)

          VStack(alignment: .leading, spacing: 4) {
            Text("Connect Detach with your daily driver")
              .font(.appFont(size: 13, weight: .medium))
              .foregroundColor(theme.textColor)

            Text("Clones your current Chrome profile once and reuses it for automation")
              .font(.appFont(size: 11))
              .foregroundColor(theme.secondaryTextColor.opacity(0.8))
          }
        }

        Button(action: { connectToDailyDriver() }) {
          HStack(spacing: 8) {
            if isDetecting && isDailyDriverMode {
              ProgressView()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)
            } else {
              Image(systemName: "arrow.triangle.2.circlepath")
                .font(.appFont(size: 12))
            }

            Text(isDailyDriverMode ? "Profile Ready" : "Clone Profile")
              .font(.appFont(size: 12, weight: .medium))
          }
          .foregroundColor(theme.backgroundColor)
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .background(theme.accentColor)
          .cornerRadius(theme.borderRadius / 1.5)
        }
        .buttonStyle(.plain)
        .disabled(isDetecting)

        if let dailyDriverStatus {
          Text(dailyDriverStatus)
            .font(.appFont(size: 11))
            .foregroundColor(theme.secondaryTextColor.opacity(0.8))
        }

        if let dailyDriverError {
          Text(dailyDriverError)
            .font(.appFont(size: 11))
            .foregroundColor(.orange)
        }
      }

      // Quick Detect Option (Fresh Browser)
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Image(systemName: "plus.app")
            .font(.appFont(size: 14))
            .foregroundColor(theme.secondaryTextColor)

          VStack(alignment: .leading, spacing: 2) {
            Text("Quick Detect (Fresh Browser)")
              .font(.appFont(size: 13, weight: .medium))
              .foregroundColor(theme.textColor)

            Text("Launch a temporary browser for testing (no login sessions)")
              .font(.appFont(size: 11))
              .foregroundColor(theme.secondaryTextColor.opacity(0.8))
          }
        }

        Button(action: { detectCdpUrl(useDailyDriver: false) }) {
          HStack(spacing: 8) {
            if isDetecting && !isDailyDriverMode {
              ProgressView()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)
            } else {
              Image(systemName: "bolt.fill")
                .font(.appFont(size: 12))
            }

            Text(!isDailyDriverMode ? detectButtonText : "Quick Detect")
              .font(.appFont(size: 11, weight: .medium))
          }
          .foregroundColor(theme.textColor.opacity(0.8))
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(theme.inputBackgroundColor)
          .cornerRadius(theme.borderRadius / 2)
          .overlay(
            RoundedRectangle(cornerRadius: theme.borderRadius / 2)
              .stroke(theme.borderColor, lineWidth: 0.5)
          )
        }
        .buttonStyle(.plain)
        .disabled(isDetecting)
      }

      // Status message
      if case .error(let message) = detectStatus {
        HStack(spacing: 6) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundColor(.orange)
          Text(message)
            .font(.appFont(size: 11))
            .foregroundColor(.orange)
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(theme.borderRadius / 2)
      }
    }
    .alert("Chrome is running", isPresented: $showDailyDriverAlert) {
      Button("Quit Chrome and Continue", role: .destructive) {
        Task {
          await quitRunningBrowsers()
          startDailyDriverClone()
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("To clone your profile safely, Chrome needs to be closed briefly.")
    }
    // .padding(16)
    // .cornerRadius(theme.borderRadius)
    // .overlay(
    //   RoundedRectangle(cornerRadius: theme.borderRadius)
    //     .stroke(theme.borderColor, lineWidth: 0.5)
    // )
  }

  @State private var isDailyDriverMode = false

  private var detectButtonText: String {
    switch detectStatus {
    case .idle: return "Quick Detect"
    case .launching: return "Launching Chrome..."
    case .querying: return "Getting CDP URL..."
    case .success: return "Re-connect"
    case .error: return "Try Again"
    }
  }

  // MARK: - Manual CDP Section

  private var manualCdpSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("CDP URL")
        .font(.appFont(size: 11, weight: .bold))
        .foregroundColor(theme.secondaryTextColor)

      HStack(spacing: 8) {
        TextField("ws://127.0.0.1:9222/devtools/browser/...", text: $cdpUrl)
          .font(.appFont(size: 13, design: .monospaced))
          .foregroundColor(theme.textColor)
          .textFieldStyle(.plain)
          .padding(10)
          .background(theme.inputBackgroundColor)
          .cornerRadius(theme.borderRadius / 1.5)
          .overlay(
            RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
              .stroke(theme.borderColor, lineWidth: 0.5)
          )
          .onChange(of: cdpUrl) { syncSettings() }

        if !cdpUrl.isEmpty {
          Button(action: { cdpUrl = "" }) {
            Image(systemName: "xmark.circle.fill")
              .font(.appFont(size: 16))
              .foregroundColor(theme.secondaryTextColor)
          }
          .buttonStyle(.plain)
        }
      }

      Text(
        "Enter the WebSocket URL for Chrome DevTools Protocol. Leave empty to launch a fresh browser."
      )
      .font(.appFont(size: 11))
      .foregroundColor(theme.secondaryTextColor.opacity(0.8))
    }
  }

  // MARK: - Browser Options Section

  private var browserOptionsSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("OPTIONS")
        .font(.appFont(size: 11, weight: .bold))
        .foregroundColor(theme.secondaryTextColor)

      // Headless Toggle
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Headless Mode")
            .font(.appFont(size: 13, weight: .medium))
            .foregroundColor(theme.textColor)

          Text("Run browser without visible window (faster, but can't observe)")
            .font(.appFont(size: 11))
            .foregroundColor(theme.secondaryTextColor.opacity(0.8))
        }

        Spacer()

        Toggle("", isOn: $headless)
          .toggleStyle(.switch)
          .tint(theme.accentColor)
          .onChange(of: headless) { syncSettings() }
      }

      // Viewport Size
      VStack(alignment: .leading, spacing: 8) {
        Text("Viewport Size")
          .font(.appFont(size: 13, weight: .medium))
          .foregroundColor(theme.textColor)

        HStack(spacing: 12) {
          HStack(spacing: 6) {
            Text("W:")
              .font(.appFont(size: 11))
              .foregroundColor(theme.secondaryTextColor)

            TextField("1280", value: $viewportWidth, format: .number)
              .font(.appFont(size: 12, design: .monospaced))
              .foregroundColor(theme.textColor)
              .textFieldStyle(.plain)
              .frame(width: 60)
              .padding(6)
              .background(theme.inputBackgroundColor)
              .cornerRadius(theme.borderRadius / 2)
              .overlay(
                RoundedRectangle(cornerRadius: theme.borderRadius / 2)
                  .stroke(theme.borderColor, lineWidth: 0.5)
              )
              .onChange(of: viewportWidth) { syncSettings() }
          }

          HStack(spacing: 6) {
            Text("H:")
              .font(.appFont(size: 11))
              .foregroundColor(theme.secondaryTextColor)

            TextField("720", value: $viewportHeight, format: .number)
              .font(.appFont(size: 12, design: .monospaced))
              .foregroundColor(theme.textColor)
              .textFieldStyle(.plain)
              .frame(width: 60)
              .padding(6)
              .background(theme.inputBackgroundColor)
              .cornerRadius(theme.borderRadius / 2)
              .overlay(
                RoundedRectangle(cornerRadius: theme.borderRadius / 2)
                  .stroke(theme.borderColor, lineWidth: 0.5)
              )
              .onChange(of: viewportHeight) { syncSettings() }
          }

          Text("px")
            .font(.appFont(size: 11))
            .foregroundColor(theme.secondaryTextColor)
        }
      }
    }
  }

  private func bulletPoint(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Text("-")
        .font(.appFont(size: 13))
        .foregroundColor(theme.accentColor)

      Text(text)
        .font(.appFont(size: 13))
        .foregroundColor(theme.secondaryTextColor.opacity(0.9))
    }
  }

  // MARK: - Auto-detect Logic

  private func connectToDailyDriver() {
    if isBrowserRunning() {
      showDailyDriverAlert = true
      return
    }
    startDailyDriverClone()
  }

  private func startDailyDriverClone() {
    Task {
      await MainActor.run {
        isDetecting = true
        isDailyDriverMode = true
        dailyDriverError = nil
        dailyDriverStatus = "Cloning Chrome profile..."
      }

      do {
        guard let browser = findAvailableBrowser() else {
          await MainActor.run {
            dailyDriverError = "No Chromium-based browser found. Install Chrome, Edge, or Brave."
            dailyDriverStatus = nil
            isDetecting = false
          }
          return
        }

        let clonePath = try cloneDailyDriverProfile(from: browser.name)
        await MainActor.run {
          useDailyDriverProfile = true
          userDataDir = clonePath
          cdpUrl = ""
          dailyDriverStatus = "Daily driver ready. Chrome will launch when the agent starts."
          isDetecting = false
          syncSettings()
        }
      } catch {
        await MainActor.run {
          dailyDriverError = "Failed to clone profile: \(error.localizedDescription)"
          dailyDriverStatus = nil
          isDetecting = false
        }
      }
    }
  }

  private func detectCdpUrl(useDailyDriver: Bool = false) {
    isDetecting = true
    detectStatus = .launching
    isDailyDriverMode = useDailyDriver

    Task {
      do {
        // Find available browser
        guard let browser = findAvailableBrowser() else {
          await MainActor.run {
            detectStatus = .error(
              "No Chromium-based browser found. Install Chrome, Edge, or Brave.")
            isDetecting = false
          }
          return
        }

        let userDataDirectory = useDailyDriver ? resolvedDailyDriverProfile() : "/tmp/lazzy-browser-detect"
        if useDailyDriver {
          await MainActor.run {
            useDailyDriverProfile = true
            userDataDir = userDataDirectory
          }
        } else {
          launchedChromeProcess?.terminate()
          launchedChromeProcess = nil
        }

        // Launch browser with debug port
        let process = Process()
        process.executableURL = URL(fileURLWithPath: browser.path)

        // Launch a debug-enabled browser
        process.arguments = [
          "--remote-debugging-port=9222",
          "--no-first-run",
          "--no-default-browser-check",
          "--user-data-dir=\(userDataDirectory)",
        ]

        try process.run()
        launchedChromeProcess = process

        // Wait for browser to start
        try await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds

        await MainActor.run {
          detectStatus = .querying
        }

        // Query the debug endpoint
        let url = URL(string: "http://127.0.0.1:9222/json/version")!
        let (data, _) = try await URLSession.shared.data(from: url)

        struct VersionResponse: Codable {
          let webSocketDebuggerUrl: String
        }

        let response = try JSONDecoder().decode(VersionResponse.self, from: data)
        let detectedUrl = response.webSocketDebuggerUrl

        await MainActor.run {
          cdpUrl = detectedUrl
          if !useDailyDriver {
            useDailyDriverProfile = false
            userDataDir = ""
          }

          detectStatus = .success(detectedUrl)
          isDetecting = false
          syncSettings()
        }

      } catch {
        // Clean up on error
        launchedChromeProcess?.terminate()
        launchedChromeProcess = nil

        await MainActor.run {
          detectStatus = .error("Failed to detect CDP URL: \(error.localizedDescription)")
          isDetecting = false
        }
      }
    }
  }

  private func getBrowserProcessName(_ browserName: String) -> String {
    switch browserName {
    case "Google Chrome": return "Google Chrome"
    case "Microsoft Edge": return "Microsoft Edge"
    case "Brave Browser": return "Brave Browser"
    case "Chromium": return "Chromium"
    default: return browserName
    }
  }

  /// Get the default user data directory for each browser
  private func getDefaultBrowserProfile(_ browserName: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    switch browserName {
    case "Google Chrome":
      return "\(home)/Library/Application Support/Google/Chrome"
    case "Microsoft Edge":
      return "\(home)/Library/Application Support/Microsoft Edge"
    case "Brave Browser":
      return "\(home)/Library/Application Support/BraveSoftware/Brave-Browser"
    case "Chromium":
      return "\(home)/Library/Application Support/Chromium"
    default:
      return "\(home)/Library/Application Support/Google/Chrome"
    }
  }

  /// Get the Lazzy Debug profile directory (separate from default Chrome profile)
  private func getLazzyDebugProfilePath() -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return "\(home)/Library/Application Support/Lazzy/BrowserDebug"
  }

  private func cloneDailyDriverProfile(from browserName: String) throws -> String {
    let sourceDir = getDefaultBrowserProfile(browserName)
    let destinationDir = getLazzyDebugProfilePath()
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: destinationDir) {
      return destinationDir
    }

    let destinationParent = (destinationDir as NSString).deletingLastPathComponent
    try fileManager.createDirectory(atPath: destinationParent, withIntermediateDirectories: true)
    try fileManager.copyItem(atPath: sourceDir, toPath: destinationDir)
    return destinationDir
  }

  private func resolvedDailyDriverProfile() -> String {
    if userDataDir.isEmpty {
      return getLazzyDebugProfilePath()
    }
    return userDataDir
  }

  private func isBrowserRunning() -> Bool {
    let runningApps = NSWorkspace.shared.runningApplications
    return runningApps.contains { app in
      guard let name = app.localizedName else { return false }
      return supportedBrowsers.map { $0.0 }.contains(name)
    }
  }

  private func quitRunningBrowsers() async {
    let runningApps = NSWorkspace.shared.runningApplications
    let browserNames = Set(supportedBrowsers.map { $0.0 })
    let browsersToQuit = runningApps.filter { app in
      guard let name = app.localizedName else { return false }
      return browserNames.contains(name)
    }

    for app in browsersToQuit {
      _ = app.terminate()
    }

    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
      let stillRunning = NSWorkspace.shared.runningApplications.contains { app in
        guard let name = app.localizedName else { return false }
        return browserNames.contains(name)
      }
      if !stillRunning {
        break
      }
      try? await Task.sleep(nanoseconds: 200_000_000)
    }
  }

  private func findAvailableBrowser() -> (name: String, path: String)? {
    for browser in supportedBrowsers {
      if FileManager.default.fileExists(atPath: browser.1) {
        return (browser.0, browser.1)
      }
    }
    return nil
  }

  // MARK: - Sync Settings

  private func syncSettings() {
    wsManager.updateBrowserSettings(
      cdpUrl: cdpUrl.isEmpty ? nil : cdpUrl,
      headless: headless,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      userDataDir: useDailyDriverProfile && !userDataDir.isEmpty ? userDataDir : nil
    )
  }
}

// MARK: - Preview

#Preview {
  BrowserSettingsView(wsManager: WebSocketManager())
    .padding()
    .frame(width: 500, height: 700)
    .background(Color(white: 0.1))
}
