import Darwin
import Foundation

@main struct PowerGuardMain {
  static func main() {
    guard geteuid() == 0 else { exit(1) }
    let service = PowerGuardService()
    let listener = NSXPCListener(machServiceName: KeepAwakeServiceIdentity.machService)
    listener.delegate = service
    listener.resume()
    dispatchMain()
  }
}
