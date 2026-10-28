import Foundation
import IOKit.ps

enum PowerSafety {
  static func stopReason() -> String? {
    if ProcessInfo.processInfo.thermalState == .critical {
      return "The Mac is too hot to keep awake."
    }
    guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let sourceType = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String? else {
      return "Detach could not check the Mac's power source."
    }
    guard sourceType == kIOPSBatteryPowerValue else { return nil }
    guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
      return "Detach could not check the battery."
    }
    for source in sources {
      guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
        let current = description[kIOPSCurrentCapacityKey] as? Int,
        let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
      return current * 100 / maximum <= 10 ? "The battery is too low to keep the Mac awake." : nil
    }
    return "Detach could not check the battery."
  }
}
