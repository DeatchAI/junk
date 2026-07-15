//
//  AppSettings.swift
//  lazzy
//
//  General application settings
//

import OSLog
import ServiceManagement
import SwiftUI

struct AppSettings {
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.lazzy.app", category: "AppSettings")

  // MARK: - Keys
  private enum Keys {
    static let launchAtLogin = "launch_at_login"
  }

  // MARK: - Properties with AppStorage

  @AppStorage(Keys.launchAtLogin)
  static var launchAtLogin: Bool = false {
    didSet {
      updateLaunchAtLogin(isEnabled: launchAtLogin)
    }
  }

  // MARK: - Methods

  /// Updates the auto-launch state using SMAppService
  static func updateLaunchAtLogin(isEnabled: Bool) {
    let service = SMAppService.mainApp

    do {
      if isEnabled {
        if service.status != .enabled {
          try service.register()
          logger.info("Successfully registered auto-launch service")
        }
      } else {
        if service.status == .enabled {
          try service.unregister()
          logger.info("Successfully unregistered auto-launch service")
        }
      }
    } catch {
      logger.error("Failed to update auto-launch service: \(error.localizedDescription)")
      // Reset the value if it fails?
      // Better to let the user know via UI if possible, but for now we'll just log.
    }
  }

  /// Synchronizes the AppStorage value with the actual SMAppService status
  static func syncLaunchAtLoginStatus() {
    let status = SMAppService.mainApp.status
    let isEnabled = status == .enabled
    if launchAtLogin != isEnabled {
      // We use the storage as source of truth usually, but on first launch or if changed outside
      // we might want to sync. For now, let's keep it simple.
      logger.debug("Syncing launch at login status: \(isEnabled)")
    }
  }
}
