//
//  lazzyApp.swift
//  lazzy
//
//  Created by Yakshit Chhipa (Govind) on 05/12/25.
//

import Combine
import SDWebImageSVGCoder
import SwiftUI

@main
struct lazzyApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @StateObject private var updaterViewModel = UpdaterViewModel()

  init() {
    // Initialize SVGCoder for SVG support
    SDImageCodersManager.shared.addCoder(SDImageSVGCoder.shared)
  }

  var body: some Scene {
    // Menu bar only - use .menu style to avoid layout cycle crashes
    MenuBarExtra {
      MenuBarContentView(appDelegate: appDelegate, updaterViewModel: updaterViewModel)
        .font(.custom("Geist-Regular", size: 13))
    } label: {
      Image("AppIcon")
        .resizable()
        .scaledToFit()
    }
    .menuBarExtraStyle(.menu)
  }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
  @Published var coordinator: AppCoordinator?
  private var cancellables = Set<AnyCancellable>()

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Initialize coordinator
    coordinator = AppCoordinator()

    // Hide dock icon - make it menu bar only
    NSApp.setActivationPolicy(.accessory)

    coordinator?.start()
    print("✅ AppDelegate started coordinator")
  }

  // /// CRITICAL: Prevent activation policy change when app is "opened" via deep link
  // /// This is called BEFORE applicationWillBecomeActive and before application(_:open:)
  // func applicationWillBecomeActive(_ notification: Notification) {
  //   // Always re-assert menu bar only mode to prevent dock icon appearing
  //   NSApp.setActivationPolicy(.accessory)
  //   print("🔒 AppDelegate: Re-asserted .accessory policy on activation")
  // }

  func applicationWillTerminate(_ notification: Notification) {
    // Stop the server when app terminates
    coordinator?.stop()
    print("🛑 App terminating - stopping server")
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      print("🔗 AppDelegate Received URL: \(url)")
      if url.scheme == "lazzy" || url.scheme == "detach" {
        if let coordinator {
          DispatchQueue.main.async {
            MenuBarContentView.showSettings(
              wsManager: coordinator.wsManager,
              onRunWorkflow: coordinator.runWorkflow
            )
          }
        }
      }
    }
  }

  private func trackAppLaunch() {
    performLaunchLogging()
  }

  private func performLaunchLogging() {
    // Check for update
    let currentVersion =
      Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    let previousVersion = UserDefaults.standard.string(forKey: "last_version")

    if let previousVersion = previousVersion, previousVersion != currentVersion {
      print("Detach updated from \(previousVersion) to \(currentVersion)")
    }

    // Update stored version
    UserDefaults.standard.set(currentVersion, forKey: "last_version")
  }
}

// CRITICAL: Re-assert menu bar only mode immediately
// When macOS opens an app via URL scheme, it tries to activate it as a regular app.
// This causes the dock icon to appear and conflicts with our .accessory policy.
// We must re-assert the policy FIRST, before doing anything else.
// NSApp.setActivationPolicy(.accessory)

//   for url in urls {
//     print("🔗 AppDelegate: Received URL: \(url)")

//     // Robust check for our custom scheme
//     guard url.scheme == "lazzy" else {
//       print("🔗 AppDelegate: Ignoring non-lazzy URL: \(url.absoluteString)")
//       continue
//     }

//     // Handle auth callback
//     // Usually "lazzy://login-callback" or contains session data in fragment
//     if url.host == "login-callback" || url.absoluteString.contains("access_token") {
//       print("🔗 AppDelegate: Identified as auth callback")
//       AuthManager.shared.handleDeeplink(url)

//       // Show settings window after a short delay to allow session to settle
//       if let wsManager = coordinator?.wsManager {
//         DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//           print("🔗 AppDelegate: Attempting to show settings window")
//           MenuBarContentView.showSettings(wsManager: wsManager)
//         }
//       }
//     } else {
//       print("🔗 AppDelegate: Received unhandled lazzy URL path: \(url.host ?? "none")")
//     }
//   }
// }

// MARK: - Menu Bar Content View (for .menu style)

struct MenuBarContentView: View {
  @ObservedObject var appDelegate: AppDelegate
  @ObservedObject var updaterViewModel: UpdaterViewModel
  @State private var showMCPSettings = false

  var body: some View {
    if let coordinator = appDelegate.coordinator {
      // Status indicator
      // HStack {
      //   Circle()
      //     .fill(coordinator.isMonitoring ? Color.green : Color.red)
      //     .frame(width: 8, height: 8)
      //   Text(coordinator.isMonitoring ? "Monitoring Active" : "Monitoring Stopped")
      // }

      // // MCP indicator
      // HStack {
      //   Image(systemName: "puzzlepiece.extension")
      //   Text(
      //     "\(coordinator.wsManager.mcpServers.filter { $0.status?.connected == true }.count) MCP Servers"
      //   )
      // }
      // .foregroundColor(.secondary)

      // Divider()

      // Permissions button
      if !coordinator.permissionsManager.hasAccessibilityPermission {
        Button("Grant Accessibility Permission") {
          coordinator.permissionsManager.requestAccessibilityPermission()
        }
      }

      if !coordinator.permissionsManager.hasScreenCapturePermission {
        Button("Grant Screen Recording Permission") {
          coordinator.permissionsManager.requestScreenCapturePermission()
        }
      }

      // Start/Stop button
      // if coordinator.isMonitoring {
      //   Button("Stop Monitoring") {
      //     coordinator.stop()
      //   }
      // } else {
      //   Button("Start Monitoring") {
      //     coordinator.start()
      //   }
      // }

      Divider()

      // MCP Settings button
      Button("Settings") {
        MenuBarContentView.showSettings(
          wsManager: coordinator.wsManager,
          onRunWorkflow: coordinator.runWorkflow
        )
      }

      Menu("Notch Debug") {
        Button("Thinking") { coordinator.showNotchDebugScenario(.thinking) }
        Button("Terminal command") { coordinator.showNotchDebugScenario(.command) }
        Button("File change") { coordinator.showNotchDebugScenario(.fileChange) }
        Button("MCP tool") { coordinator.showNotchDebugScenario(.mcpTool) }
        Button("Plan update") { coordinator.showNotchDebugScenario(.plan) }
        Divider()
        Button("Approval request") { coordinator.showNotchDebugScenario(.approval) }
        Button("Failure") { coordinator.showNotchDebugScenario(.failure) }
        Button("Completed") { coordinator.showNotchDebugScenario(.completed) }
        Button("Multiple agents") { coordinator.showNotchDebugScenario(.multiAgent) }
        Button("Multiple states") { coordinator.showNotchDebugScenario(.multiMixedStates) }
        Divider()
        Button("Clear notch") { coordinator.showNotchDebugScenario(.clear) }
      }

      Divider()

      // Text("📁 In Finder: select files + press ⌥")
      //   .font(.caption)

      // Divider()

      // Button("Show onboarding") {
      //   OnboardingWindowController().show()
      // }

      Button("Check for Updates...") {
        updaterViewModel.checkForUpdates()
      }
      .disabled(!updaterViewModel.canCheckForUpdates)

      Button("Quit Detach") {
        NSApplication.shared.terminate(nil)
      }
      .keyboardShortcut("q")
    } else {
      Text("Initializing...")
    }
  }

  // Store a reference to prevent deallocation
  static var settingsWindowController: NSWindowController?

  static func showSettings(
    wsManager: WebSocketManager,
    onRunWorkflow: ((QuickAction) -> Void)? = nil,
    launchIntent: SettingsLaunchIntent? = nil
  ) {
    NSApp.activate(ignoringOtherApps: true)

    // If window already exists, just bring it to front
    if let existingController = Self.settingsWindowController,
      let existingWindow = existingController.window
    {
      existingWindow.contentView = NSHostingView(
        rootView: SettingsView(
          wsManager: wsManager,
          onRunWorkflow: onRunWorkflow,
          launchIntent: launchIntent
        )
      )
      existingWindow.makeKeyAndOrderFront(nil)
      return
    }

    // Create new window
    let window = KeyableWindow(
      contentRect: NSRect(x: 0, y: 0, width: 730, height: 600),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.isMovableByWindowBackground = true
    window.backgroundColor = .clear
    window.isOpaque = false
    window.hasShadow = true
    window.isReleasedWhenClosed = false

    // Create hosting view
    let hostingView = NSHostingView(
      rootView: SettingsView(
        wsManager: wsManager,
        onRunWorkflow: onRunWorkflow,
        launchIntent: launchIntent
      )
    )
    window.contentView = hostingView

    // Create and retain window controller
    let controller = NSWindowController(window: window)
    Self.settingsWindowController = controller

    window.center()
    controller.showWindow(nil)
  }
}
