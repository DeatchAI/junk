import AppKit
import ApplicationServices

@main struct DesktopContractTests {
  @MainActor static func main() async throws {
    let rect = CGRect(x: -1440, y: 30, width: 1440, height: 900)
    let mapped = try DesktopGeometry.mapPixel(CGPoint(x: 720, y: 450), image: CGSize(width: 1440, height: 900), window: rect)
    precondition(mapped == CGPoint(x: -720, y: 480))
    let retina = try DesktopGeometry.mapPixel(CGPoint(x: 1000, y: 500), image: CGSize(width: 2000, height: 1000),
      window: CGRect(x: 100, y: 80, width: 1000, height: 500))
    precondition(retina == CGPoint(x: 600, y: 330))
    for point in [CGPoint(x: -1, y: 0), CGPoint(x: 1440, y: 0), CGPoint(x: CGFloat.infinity, y: 1)] {
      do { _ = try DesktopGeometry.mapPixel(point, image: CGSize(width: 1440, height: 900), window: rect); fatalError("Invalid coordinate accepted") }
      catch {}
    }
    let selectionCheck15 = try DesktopGeometry.replacingSelection(in: "hello world", range: NSRange(location: 6, length: 5), with: "Detach") == "hello Detach"
    precondition(selectionCheck15)
    let selectionCheck16 = try DesktopGeometry.replacingSelection(in: "ab", range: NSRange(location: 1, length: 0), with: "🙂") == "a🙂b"
    precondition(selectionCheck16)
    let selectionCheck17 = try DesktopGeometry.replacingSelection(in: "a🙂b", range: NSRange(location: 1, length: 2), with: "x") == "axb"
    precondition(selectionCheck17)
    do { _ = try DesktopGeometry.replacingSelection(in: "a🙂b", range: NSRange(location: 2, length: 0), with: "x"); fatalError("Split surrogate accepted") }
    catch {}
    do { _ = try DesktopGeometry.replacingSelection(in: "x", range: NSRange(location: Int.max, length: 2), with: "y"); fatalError("Out of range selection accepted") }
    catch {}
    let service = DesktopAutomationService()
    service.endSession("stopped-before-dispatch")
    do {
      _ = try await service.execute(command: "desktop.observe", payload: ["_sessionId": "stopped-before-dispatch"])
      fatalError("Stopped session resurrected")
    } catch let error as DesktopAutomationError { precondition(error.code == "cancelled") }
    do {
      _ = try await service.execute(command: "desktop.click", payload: [:])
      fatalError("Unscoped input accepted")
    } catch let error as DesktopAutomationError { precondition(error.code == "session_required") }
    let a = DesktopSession(id: "a"), b = DesktopSession(id: "b")
    service.sessions[a.id] = a; service.sessions[b.id] = b
    service.endSession(a.id)
    precondition(a.cancelled && !b.cancelled && service.sessions[b.id] != nil)
    do { try service.checkSession(b, ["_deadline": Date().timeIntervalSince1970 - 1]); fatalError("Expired operation accepted") }
    catch let error as DesktopAutomationError { precondition(error.code == "deadline_exceeded") }
    print("Desktop contract checks passed: selection, Unicode, Retina/multi-monitor mapping, task isolation, cancellation and deadlines")
  }
}
