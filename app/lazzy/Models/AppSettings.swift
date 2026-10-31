//
//  AppSettings.swift
//  lazzy
//
//  General application settings
//

import Foundation

struct AppSettings {
  static let notchLiveActivitiesKey = "notch_live_activities_enabled"
  static let activityIslandPlacementKey = "activity_island_placement"
  static let appPresentationModeKey = "app_presentation_mode"

  static var notchLiveActivitiesEnabled: Bool {
    UserDefaults.standard.object(forKey: notchLiveActivitiesKey) as? Bool ?? true
  }

  static var activityIslandPlacement: ActivityIslandPlacement {
    ActivityIslandPlacement(
      rawValue: UserDefaults.standard.string(forKey: activityIslandPlacementKey) ?? ""
    ) ?? .defaultPlacement
  }

  /// History occupies the other side so it never covers the live activity panel.
  static var historyPanelPlacement: ActivityIslandPlacement {
    activityIslandPlacement == .left ? .right : .left
  }

}
