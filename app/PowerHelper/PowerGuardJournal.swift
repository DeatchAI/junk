import Darwin
import Foundation

/// The directory is root-owned and private; the app never writes this record.
struct SystemPowerGuardJournal: PowerGuardJournal {
  private let directory = URL(fileURLWithPath: "/var/db/app.getlazzy.keep-awake", isDirectory: true)
  private var record: URL { directory.appendingPathComponent("recovery.json") }

  private struct Record: Codable {
    let version: Int
    let previousSleepDisabled: Bool
  }

  func hasPendingChange() throws -> Bool {
    try prepareDirectory()
    guard FileManager.default.fileExists(atPath: record.path) else { return false }
    var info = stat()
    guard lstat(record.path, &info) == 0, info.st_uid == 0,
      (info.st_mode & S_IFMT) == S_IFREG else { throw PowerGuardError.invalidJournal }
    let data = try Data(contentsOf: record)
    guard let saved = try? JSONDecoder().decode(Record.self, from: data),
      saved.version == 1, !saved.previousSleepDisabled else { throw PowerGuardError.invalidJournal }
    return true
  }

  func recordPendingChange() throws {
    try prepareDirectory()
    let data = try JSONEncoder().encode(Record(version: 1, previousSleepDisabled: false))
    try data.write(to: record, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: record.path)
    let file = try FileHandle(forWritingTo: record)
    defer { try? file.close() }
    try file.synchronize()
    let directoryFD = open(directory.path, O_RDONLY)
    guard directoryFD >= 0 else { throw PowerGuardError.invalidJournal }
    defer { close(directoryFD) }
    guard fsync(directoryFD) == 0 else { throw PowerGuardError.invalidJournal }
  }

  func clearPendingChange() throws {
    try prepareDirectory()
    if FileManager.default.fileExists(atPath: record.path) {
      try FileManager.default.removeItem(at: record)
    }
  }

  private func prepareDirectory() throws {
    var info = stat()
    if lstat(directory.path, &info) != 0 {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
    }
    guard lstat(directory.path, &info) == 0, info.st_uid == 0,
      (info.st_mode & S_IFMT) == S_IFDIR, (info.st_mode & 0o077) == 0 else {
      throw PowerGuardError.invalidJournal
    }
  }
}
