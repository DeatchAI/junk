import SwiftUI

struct KeepAwakeMenuSection: View {
  @ObservedObject var controller: KeepAwakeController

  var body: some View {
    Toggle("Keep Mac awake", isOn: Binding(
      get: { controller.isEnabled },
      set: { controller.setEnabled($0) }
    ))
    .help("Keeps the Mac awake while agents are working.")
    if let message = controller.message {
      Text(message).disabled(true)
    }
  }
}
