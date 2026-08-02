import Auth
import Supabase
import SwiftUI

struct AccountSettingsView: View {
  @StateObject private var auth = AuthManager.shared
  @StateObject private var hostedSubscription = HostedSubscriptionManager.shared
  @State private var email = ""
  @State private var magicLinkSent = false

  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if auth.isAuthenticated, let user = auth.currentUser {
          authenticatedView(user: user)
        } else {
          loginView
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 10)
    }
    .task(id: auth.isAuthenticated) {
      await hostedSubscription.refresh()
    }
  }

  private func authenticatedView(user: User) -> some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(spacing: 16) {
        // Profile Avatar Placeholder
        Circle()
          .fill(theme.accentColor.opacity(0.1))
          .frame(width: 60, height: 60)
          .overlay(
            Text(user.email?.prefix(1).uppercased() ?? "U")
              // .font(.appFont(size: 24, weight: .bold))
              .font(.custom("Sick-Regular", size: 24))
              .foregroundColor(theme.accentColor)
          )

        VStack(alignment: .leading, spacing: 4) {
          Text(user.email ?? "No email")
            .font(.appFont(size: 16, weight: .medium))
            .foregroundColor(theme.textColor)

          Text(user.role ?? "Free")
            .font(.appFont(size: 12))
            .foregroundColor(theme.textColor.opacity(0.5))
        }
      }
      .padding(.bottom, 10)

      Divider()
        .background(theme.textColor.opacity(0.1))

      VStack(alignment: .leading, spacing: 8) {
        Text("Account Management")
          .font(.appFont(size: 13, weight: .semibold))
          .foregroundColor(theme.textColor)

        Button(action: {
          Task {
            await auth.signOut()
          }
        }) {
          HStack {
            Image(systemName: "rectangle.portrait.and.arrow.right")
            Text("Sign Out")
          }
          .font(.appFont(size: 12))
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(theme.accentColor.opacity(0.3))
          .foregroundColor(theme.accentColor)
          .cornerRadius(theme.borderRadius / 1.5)
        }
        .buttonStyle(.plain)
      }

      hostedSubscriptionSection
    }
  }

  private var hostedSubscriptionSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Hosted AI credits")
        .font(.appFont(size: 13, weight: .semibold))
        .foregroundColor(theme.textColor)

      VStack(alignment: .leading, spacing: 12) {
        if hostedSubscription.isLoading && hostedSubscription.credits == nil {
          ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .center)
        } else if let credits = hostedSubscription.credits {
          HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
              Text("Available")
                .font(.appFont(size: 11))
                .foregroundColor(theme.textColor.opacity(0.6))

              if let progress = hostedSubscription.availableCreditProgress,
                let percentage = hostedSubscription.availableCreditPercentage
              {
                HostedCreditsProgressView(progress: progress, percentage: percentage)
              }

              Text("\(credits.available) credits remaining")
                .font(.appFont(size: 20, weight: .bold))
                .foregroundColor(theme.textColor)
            }
            Spacer()
            if let subscription = hostedSubscription.subscription {
              VStack(alignment: .trailing, spacing: 3) {
                Text(subscription.displayName)
                  .font(.appFont(size: 12, weight: .semibold))
                Text(subscription.cancelAtPeriodEnd ? "Ends this period" : "Active")
                  .font(.appFont(size: 10))
                  .foregroundColor(theme.textColor.opacity(0.55))
              }
            }
          }

          if credits.reserved != "0" {
            Text("\(credits.reserved) credits are reserved for active hosted tasks.")
              .font(.appFont(size: 10))
              .foregroundColor(theme.textColor.opacity(0.5))
          }

          if credits.amountDue != "0" {
            Text("\(credits.amountDue) credits are pending reconciliation.")
              .font(.appFont(size: 10))
              .foregroundColor(.orange)
          }
        }

        if hostedSubscription.subscription != nil {
          Button {
            Task { await hostedSubscription.openCustomerPortal() }
          } label: {
            Text(hostedSubscription.isLoading ? "Opening…" : "Manage subscription")
              .font(.appFont(size: 12, weight: .medium))
          }
          .buttonStyle(.plain)
          .padding(.horizontal, 12)
          .padding(.vertical, 7)
          .background(theme.accentColor.opacity(0.2))
          .foregroundColor(theme.accentColor)
          .cornerRadius(theme.borderRadius / 1.5)
          .disabled(hostedSubscription.isLoading)
        } else if hostedSubscription.hasHostedCredits {
          Text("Hosted access is active. Subscription details are still syncing.")
            .font(.appFont(size: 10))
            .foregroundColor(theme.textColor.opacity(0.55))
        } else if !hostedSubscription.plans.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text("Choose a monthly allocation")
              .font(.appFont(size: 11))
              .foregroundColor(theme.textColor.opacity(0.6))
            ForEach(hostedSubscription.plans) { plan in
              Button {
                Task { await hostedSubscription.startCheckout(planId: plan.id) }
              } label: {
                HStack {
                  VStack(alignment: .leading, spacing: 2) {
                    Text(plan.displayName)
                      .font(.appFont(size: 12, weight: .semibold))
                    Text("\(plan.monthlyCredits.formatted()) hosted credits / month")
                      .font(.appFont(size: 10))
                      .foregroundColor(theme.textColor.opacity(0.55))
                  }
                  Spacer()
                  Text("$\(plan.monthlyPriceCents / 100)/mo")
                    .font(.appFont(size: 12, weight: .medium))
                }
                .padding(.vertical, 4)
              }
              .buttonStyle(.plain)
              .disabled(hostedSubscription.isLoading)
            }
          }
        }

        if let error = hostedSubscription.errorMessage {
          Text(error)
            .font(.appFont(size: 10))
            .foregroundColor(.red)
        }
      }
      .padding(16)
      .background(theme.textColor.opacity(0.03))
      .cornerRadius(theme.borderRadius / 1.5)
      .overlay(
        RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
          .stroke(theme.textColor.opacity(0.05), lineWidth: 1)
      )
    }
  }

  private var legacyPlanAndUsageSection: some View {
    VStack(alignment: .leading, spacing: 16) {
        Text("Plan & Usage")
          .font(.appFont(size: 13, weight: .semibold))
          .foregroundColor(theme.textColor)

        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text("Current Plan:")
              .font(.appFont(size: 12))
              .foregroundColor(theme.textColor.opacity(0.6))
            Text(auth.userProfile?.planType.displayName ?? "Free")
              .font(.appFont(size: 12, weight: .bold))
              .foregroundColor(theme.accentColor)

            Spacer()

            if auth.userProfile?.planType == .free {
              Link(destination: URL(string: "https://getlazzy.app/pricing")!) {
                Text("Upgrade")
                  .font(.appFont(size: 11, weight: .medium))
                  .padding(.horizontal, 8)
                  .padding(.vertical, 4)
                  .background(theme.accentColor)
                  .foregroundColor(.white)
                  .cornerRadius(4)
              }
              .buttonStyle(.plain)
            }
          }

          if let usage = auth.usage {
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text("AI Usage:")
                  .font(.appFont(size: 11))
                Spacer()
                Text("\(Int(usage.creditsUsed)) / \(usage.creditLimit) credits")
                  .font(.appFont(size: 11))
              }
              .foregroundColor(theme.textColor.opacity(0.6))

              // Usage Progress Bar
              ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                  .fill(theme.textColor.opacity(0.1))
                  .frame(height: 6)

                RoundedRectangle(cornerRadius: 2)
                  .fill(usage.usageProgress > 0.9 ? Color.red : theme.accentColor)
                  .frame(width: 240 * CGFloat(usage.usageProgress), height: 6)
              }

              Text("Credits reset on \(usage.formattedResetDate)")
                .font(.appFont(size: 10))
                .foregroundColor(theme.textColor.opacity(0.4))
                .padding(.top, 2)
            }
          } else {
            ProgressView()
              .controlSize(.small)
              .frame(maxWidth: .infinity, alignment: .center)
          }
        }
        .padding(16)
        .background(theme.textColor.opacity(0.03))
        .cornerRadius(theme.borderRadius / 1.5)
        .overlay(
          RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
            .stroke(theme.textColor.opacity(0.05), lineWidth: 1)
        )
      }
    }
  private var loginView: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 8) {
        Text("Sign in to Detach")
          .font(.appFont(size: 18, weight: .bold))
          .foregroundColor(theme.textColor)

        Text(
          "Use Detach-hosted models and manage your monthly credit allocation. Local agents remain available without an account."
        )
          .font(.appFont(size: 13))
          .foregroundColor(theme.textColor.opacity(0.6))
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(alignment: .leading, spacing: 12) {
        Text("Magic Link")
          .font(.appFont(size: 12, weight: .semibold))
          .foregroundColor(theme.textColor.opacity(0.4))

        HStack(spacing: 12) {
          TextField("", text: $email)
            .placeholder(when: email.isEmpty) {
              Text("Email address").foregroundColor(theme.textColor.opacity(0.4))
            }
            .textFieldStyle(.plain)
            .padding(8)
            .background(theme.textColor.opacity(0.05))
            .cornerRadius(theme.borderRadius / 2)
            .overlay(
              RoundedRectangle(cornerRadius: theme.borderRadius / 2)
                .stroke(theme.textColor.opacity(0.1), lineWidth: 1)
            )

          Button(action: {
            Task {
              await auth.signInWithMagicLink(email: email)
              magicLinkSent = true
            }
          }) {
            if auth.isLoading {
              ProgressView()
                .controlSize(.small)
            } else {
              Text("Send Link")
                .font(.appFont(size: 12, weight: .medium))
            }
          }
          .buttonStyle(.plain)
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .background(theme.accentColor)
          .foregroundColor(theme.backgroundColor)
          .cornerRadius(theme.borderRadius / 2)
          .disabled(email.isEmpty || auth.isLoading)
        }

        if magicLinkSent {
          Text("Check your email for the login link!")
            .font(.appFont(size: 11))
            .foregroundColor(theme.accentColor)
        }
      }
      .padding(.top, 10)

      HStack {
        Rectangle()
          .fill(theme.textColor.opacity(0.1))
          .frame(height: 1)
        Text("OR")
          .font(.appFont(size: 10, weight: .bold))
          .foregroundColor(theme.textColor.opacity(0.3))
        Rectangle()
          .fill(theme.textColor.opacity(0.1))
          .frame(height: 1)
      }
      .padding(.vertical, 10)

      VStack(spacing: 12) {
        // SocialLoginButton(title: "Continue with GitHub", provider: .github)
        SocialLoginButton(title: "Continue with Google", provider: .google)
        // SocialLoginButton(title: "Continue with Discord", provider: .discord)
        // SocialLoginButton(title: "Continue with Twitter/X", provider: .twitter)
      }

      if let error = auth.lastError {
        Text(error)
          .font(.appFont(size: 11))
          .foregroundColor(.red)
          .padding(.top, 10)
      }
    }
  }
}

struct HostedCreditsProgressView: View {
  let progress: Double
  let percentage: Int

  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    HStack(spacing: 12) {
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          Capsule()
            .fill(theme.textColor.opacity(0.1))

          Capsule()
            .fill(theme.textColor.opacity(0.9))
            .frame(width: geometry.size.width * progress)
        }
      }
      .frame(height: 8)

      Text("\(percentage)% left")
        .font(.appFont(size: 12, weight: .medium))
        .foregroundColor(theme.textColor.opacity(0.65))
        .fixedSize()
    }
  }
}
