import Foundation

/// Public configuration required for a clean, open-source build.
///
/// A Supabase publishable key identifies the project; it is not a provider
/// credential and is safe to ship when Row Level Security is configured. All
/// Detach-owned provider keys belong in the hosted control plane instead.
enum AppConfiguration {
  static let supabaseURL = "https://qymrzmmsroxkteaxbgoo.supabase.co"
  static let supabasePublishableKey = "sb_publishable_aWjjz60k2uciZe45sFGzSg_11quNmaV"

  /// Open-source builds do not send product analytics. A release build may
  /// supply a non-sensitive write key through its build configuration later.
  static let analyticsWriteKey: String? = nil
}
