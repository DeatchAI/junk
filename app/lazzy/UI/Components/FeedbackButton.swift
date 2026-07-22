//
//  FeedbackButton.swift
//  lazzy
//
//  Feedback button with popover form for collecting user feedback
//

import Supabase
import SwiftUI

struct FeedbackButton: View {
  @ObservedObject private var theme = ThemeManager.shared
  @ObservedObject private var auth = AuthManager.shared

  @State private var isPopoverShown = false
  @State private var isHovered = false
  @State private var feedbackText = ""
  @State private var selectedSentiment: Sentiment? = nil
  @State private var isSubmitting = false
  @State private var submitSuccess = false
  @State private var submitError: String? = nil

  enum Sentiment: String, CaseIterable {
    case veryConfused = "very_confused"
    case confused = "confused"
    case neutral = "neutral"
    case happy = "happy"

    var emoji: String {
      switch self {
      case .veryConfused: return "😰"
      case .confused: return "😕"
      case .neutral: return "🙂"
      case .happy: return "🤩"
      }
    }
  }

  var body: some View {
    Button(action: { isPopoverShown.toggle() }) {
      Text("Feedback")
       .font(.appFont(size: 11))
          .foregroundColor(theme.textColor)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(Color.clear)
          .cornerRadius(theme.borderRadius / 1.5)
          .overlay(
            RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
              .stroke(
                theme.textColor.opacity(0.6), lineWidth: 1
              )
          )
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .help("Provide your feedback")
    .popover(isPresented: $isPopoverShown, arrowEdge: .trailing) {
      feedbackForm
    }
  }

  private var feedbackForm: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Text Editor
      ZStack(alignment: .topLeading) {
        if feedbackText.isEmpty {
          Text("Your feedback...")
            .font(.appFont(size: 13))
            .foregroundColor(theme.textColor.opacity(0.4))
            .padding(.horizontal, 8)
            // .padding(.vertical, 10)
        }

        TextEditor(text: $feedbackText)
          .font(.appFont(size: 13))
          .foregroundColor(theme.textColor)
          .scrollContentBackground(.hidden)
          .background(Color.clear)
          .frame(minHeight: 100)
      }
      .padding(.horizontal, 4)
      .padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: theme.borderRadius / 2)
          .stroke(theme.textColor.opacity(0.2), lineWidth: 1)
      )

      Divider()
        .background(theme.textColor.opacity(0.1))

      // Sentiment and Submit Row
      HStack {
        // Emoji Sentiment Buttons
        HStack(spacing: 8) {
          ForEach(Sentiment.allCases, id: \.self) { sentiment in
            Button(action: {
              selectedSentiment = sentiment
            }) {
              Text(sentiment.emoji)
                .font(.system(size: 20))
                .opacity(selectedSentiment == sentiment ? 1.0 : 0.5)
                .scaleEffect(selectedSentiment == sentiment ? 1.1 : 1.0)
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.2), value: selectedSentiment)
          }
        }

        Spacer()

        // Submit Button
        Button(action: submitFeedback) {
          if isSubmitting {
            ProgressView()
              .scaleEffect(0.7)
              .frame(width: 50)
          } else if submitSuccess {
            HStack(spacing: 4) {
              Image(systemName: "checkmark")
              Text("Sent!")
            }
            .font(.appFont(size: 12, weight: .medium))
            .foregroundColor(theme.backgroundColor)
          } else {
            Text("Send")
              .font(.appFont(size: 12, weight: .medium))
              .foregroundColor(theme.backgroundColor)
          }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
          RoundedRectangle(cornerRadius: theme.borderRadius / 2)
            .fill(submitSuccess ? Color.green : theme.textColor)
        )
        .disabled(feedbackText.isEmpty || isSubmitting)
        .opacity(feedbackText.isEmpty ? 0.5 : 1.0)
      }

      // Error message
      if let error = submitError {
        Text(error)
          .font(.appFont(size: 11))
          .foregroundColor(.red)
      }
    }
    .padding(16)
    .frame(width: 320)
    .background(theme.backgroundColor)
  }

  private func submitFeedback() {
    guard !feedbackText.isEmpty else { return }

    isSubmitting = true
    submitError = nil

    Task {
      do {
        let feedback = FeedbackEntry(
          userId: auth.currentUser?.id,
          feedback: feedbackText,
          sentiment: selectedSentiment?.rawValue
        )

        try await auth.supabase
          .from("feedbacks")
          .insert(feedback)
          .execute()

        await MainActor.run {
          isSubmitting = false
          submitSuccess = true

          // Reset and close after a delay
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            feedbackText = ""
            selectedSentiment = nil
            submitSuccess = false
            isPopoverShown = false
          }
        }
      } catch {
        await MainActor.run {
          isSubmitting = false
          submitError = "Failed to submit: \(error.localizedDescription)"
          print("❌ Feedback submission error: \(error)")
        }
      }
    }
  }
}

// MARK: - Feedback Entry Model

struct FeedbackEntry: Encodable {
  let userId: UUID?
  let feedback: String
  let sentiment: String?

  enum CodingKeys: String, CodingKey {
    case userId = "user_id"
    case feedback
    case sentiment
  }
}

#Preview {
  FeedbackButton()
    .padding()
    .background(Color.gray.opacity(0.2))
}
