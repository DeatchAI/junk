import Darwin
import Foundation
import IOKit

struct SystemPowerBackend: PowerGuardBackend {
  func sleepIsDisabled() throws -> Bool {
    guard let value = readPowerDomainProperty("SleepDisabled") as? Bool else {
      throw PowerGuardError.unreadablePowerState
    }
    return value
  }

  func setSleepDisabled(_ disabled: Bool) throws {
    try runPowerCommand(["-a", "disablesleep", disabled ? "1" : "0"])
  }
}

func readPowerDomainProperty(_ name: String) -> Any? {
  let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
  guard service != 0 else { return nil }
  defer { IOObjectRelease(service) }
  return IORegistryEntryCreateCFProperty(service, name as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
}

func runPowerCommand(_ arguments: [String]) throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
  process.arguments = arguments
  process.standardOutput = FileHandle.nullDevice
  process.standardError = FileHandle.nullDevice
  try process.run()
  let deadline = ProcessInfo.processInfo.systemUptime + 5
  while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.05) }
  if process.isRunning {
    process.terminate()
    let grace = ProcessInfo.processInfo.systemUptime + 2
    while process.isRunning && ProcessInfo.processInfo.systemUptime < grace { Thread.sleep(forTimeInterval: 0.05) }
    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    process.waitUntilExit()
    throw PowerGuardError.commandFailed
  }
  process.waitUntilExit()
  guard process.terminationStatus == 0 else { throw PowerGuardError.commandFailed }
}
