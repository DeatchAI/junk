import SwiftUI

struct LicenseSettingsView: View {
  @ObservedObject private var license = LicenseManager.shared
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        SettingsPageHeader(title: "License", subtitle: "Manage Detach access on this Mac.")
        SettingsCard {
          VStack(alignment: .leading, spacing: 14) {
            Text(license.statusDescription).font(.appFont(size: 14))
            if let key = license.displayKey {
              Text(key).font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.secondaryTextColor)
            }
            HStack(spacing: 12) {
              Button("Buy Detach") { license.openCheckout() }
              Button("Customer portal") { license.openPortal() }
              if license.hasSavedLicense {
                Button("Check license") { Task { await license.refresh(force: true) } }
                LicenseDeactivateButton()
              }
            }
            .disabled(license.isWorking)
          }.padding(18)
        }
        if license.status != .licensed && license.status != .offline {
          SettingsCard {
            LicenseKeyEntryForm().font(.appFont(size: 13)).padding(18)
          }
        } else if let message = license.message {
          Text(message).font(.appFont(size: 12)).foregroundStyle(theme.secondaryTextColor)
        }
      }
    }
  }
}
