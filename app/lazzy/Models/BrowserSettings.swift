//
//  BrowserSettings.swift
//  lazzy
//
//  User-configurable browser automation settings persisted in UserDefaults
//

import SwiftUI

enum BrowserAutomationMode: String, CaseIterable, Identifiable {
  case signedIn = "signed_in"
  case power

  var id: String { rawValue }

  var title: String {
    switch self {
    case .signedIn: return "Signed-in Chrome"
    case .power: return "Power Browser"
    }
  }

  var subtitle: String {
    switch self {
    case .signedIn: return "Uses your current Chrome logins through the Detach extension"
    case .power: return "Uses a separate, isolated Chrome with deeper and faster control"
    }
  }
}

struct BrowserSettings {

  // MARK: - Keys
  private enum Keys {
    static let mode = "browser_automation_mode"
    static let cdpUrl = "browser_cdp_url"
    static let headless = "browser_headless"
    static let viewportWidth = "browser_viewport_width"
    static let viewportHeight = "browser_viewport_height"
    static let useDailyDriverProfile = "browser_use_daily_driver"
    static let userDataDir = "browser_user_data_dir"
  }

  // MARK: - Defaults
  static let defaultCdpUrl = ""
  static let defaultMode = BrowserAutomationMode.signedIn.rawValue
  static let defaultHeadless = false
  static let defaultViewportWidth = 1280
  static let defaultViewportHeight = 720
  static let defaultUseDailyDriverProfile = false
  static let defaultUserDataDir = ""

  // MARK: - Properties with AppStorage persistence

  @AppStorage(Keys.cdpUrl)
  static var cdpUrl: String = defaultCdpUrl

  @AppStorage(Keys.mode)
  static var modeRawValue: String = defaultMode

  static var mode: BrowserAutomationMode {
    get { BrowserAutomationMode(rawValue: modeRawValue) ?? .signedIn }
    set { modeRawValue = newValue.rawValue }
  }

  @AppStorage(Keys.headless)
  static var headless: Bool = defaultHeadless

  @AppStorage(Keys.viewportWidth)
  static var viewportWidth: Int = defaultViewportWidth

  @AppStorage(Keys.viewportHeight)
  static var viewportHeight: Int = defaultViewportHeight

  @AppStorage(Keys.useDailyDriverProfile)
  static var useDailyDriverProfile: Bool = defaultUseDailyDriverProfile

  @AppStorage(Keys.userDataDir)
  static var userDataDir: String = defaultUserDataDir

  // MARK: - Reset

  static func resetToDefaults() {
    modeRawValue = defaultMode
    cdpUrl = defaultCdpUrl
    headless = defaultHeadless
    viewportWidth = defaultViewportWidth
    viewportHeight = defaultViewportHeight
    useDailyDriverProfile = defaultUseDailyDriverProfile
    userDataDir = defaultUserDataDir
  }
}
