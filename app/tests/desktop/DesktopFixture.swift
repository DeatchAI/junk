import AppKit

@main struct DesktopFixture {
  @MainActor static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let window = NSWindow(contentRect: NSRect(x: 180, y: 180, width: 500, height: 280),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = "Detach Desktop Fixture"
    window.isReleasedWhenClosed = false
    let field = NSTextField(string: "hello world")
    field.frame = NSRect(x: 24, y: 185, width: 450, height: 28)
    field.identifier = NSUserInterfaceItemIdentifier("detach.fixture.field")
    field.setAccessibilityIdentifier("detach.fixture.field")
    field.setAccessibilityLabel("Detach fixture text")
    let button = NSButton(title: "Increment", target: nil, action: nil)
    button.frame = NSRect(x: 24, y: 125, width: 120, height: 30)
    button.setAccessibilityIdentifier("detach.fixture.button")
    let slider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    slider.frame = NSRect(x: 24, y: 70, width: 450, height: 25)
    slider.setAccessibilityIdentifier("detach.fixture.slider")
    window.contentView?.addSubview(field)
    window.contentView?.addSubview(button)
    window.contentView?.addSubview(slider)
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    app.run()
  }
}
