import SwiftUI

/// The image/video settings surface is intentionally a compact in-app tray,
/// not an AppKit menu. It keeps the composer stable while making every option
/// visible at once and preserving the floating window's visual language.
struct MediaConfigurationTray: View {
  let model: MediaModelCapability?
  @Binding var config: MediaGenerationConfig

  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 8) {
          Image(systemName: "slider.horizontal.3")
            .font(.appFont(size: 12, weight: .semibold))
            .foregroundColor(theme.accentColor)
          VStack(alignment: .leading, spacing: 2) {
            Text("Generation settings")
              .font(.appFont(size: 13, weight: .semibold))
              .foregroundColor(theme.textColor)
            Text(model?.displayName ?? "Choose a model to configure it")
              .font(.appFont(size: 10))
              .foregroundColor(theme.secondaryTextColor)
              .lineLimit(1)
          }
        }

        if let model {
          settings(for: model)
        } else {
          Text("Loading available settings…")
            .font(.appFont(size: 11))
            .foregroundColor(theme.secondaryTextColor)
            .padding(.vertical, 6)
        }
      }
      .padding(14)
    }
    .frame(width: 296, height: trayHeight)
    .background(trayBackground)
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(theme.textColor.opacity(0.1), lineWidth: 0.5)
    }
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  @ViewBuilder
  private func settings(for model: MediaModelCapability) -> some View {
    if !model.aspectRatios.isEmpty {
      optionSection(
        title: "Aspect ratio",
        options: model.aspectRatios,
        selectedID: config.aspectRatio,
        onSelect: { config.aspectRatio = $0 }
      )
    }

    if !model.resolutions.isEmpty {
      optionSection(
        title: "Quality",
        options: model.resolutions,
        selectedID: config.resolution,
        onSelect: { config.resolution = $0 }
      )
    }

    if let durations = model.durations, !durations.isEmpty {
      durationSection(durations)
    }

    if !model.outputFormats.isEmpty {
      optionSection(
        title: "Output format",
        options: model.outputFormats,
        selectedID: config.outputFormat ?? model.outputFormats.first?.id,
        onSelect: { config.outputFormat = $0 }
      )
    }

    if model.supportsAudio {
      audioSection
    }
  }

  private func optionSection(
    title: String,
    options: [MediaConfigOption],
    selectedID: String?,
    onSelect: @escaping (String) -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(title)
        .font(.appFont(size: 10, weight: .medium))
        .foregroundColor(theme.secondaryTextColor)

      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 74), spacing: 6)],
        alignment: .leading,
        spacing: 6
      ) {
        ForEach(options) { option in
          MediaConfigurationChoiceButton(
            title: option.label,
            isSelected: selectedID == option.id,
            action: { onSelect(option.id) }
          )
        }
      }
    }
  }

  private func durationSection(_ durations: [Int]) -> some View {
    let currentIndex = durations.firstIndex(of: config.duration ?? durations[0]) ?? 0
    let currentDuration = durations[currentIndex]

    return VStack(alignment: .leading, spacing: 7) {
      Text("Duration")
        .font(.appFont(size: 10, weight: .medium))
        .foregroundColor(theme.secondaryTextColor)

      HStack(spacing: 8) {
        MediaDurationStepButton(
          systemImage: "minus",
          isEnabled: currentIndex > 0,
          action: { config.duration = durations[currentIndex - 1] }
        )

        Text("\(currentDuration) seconds")
          .font(.appFont(size: 11, weight: .semibold))
          .foregroundColor(theme.textColor)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 7)
          .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(theme.textColor.opacity(0.04))
          )
          .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .stroke(theme.textColor.opacity(0.1), lineWidth: 0.5)
          )

        MediaDurationStepButton(
          systemImage: "plus",
          isEnabled: currentIndex < durations.count - 1,
          action: { config.duration = durations[currentIndex + 1] }
        )
      }
    }
  }

  private var audioSection: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("Generated audio")
        .font(.appFont(size: 10, weight: .medium))
        .foregroundColor(theme.secondaryTextColor)

      HStack(spacing: 6) {
        MediaConfigurationChoiceButton(
          title: "Off",
          isSelected: config.audio != true,
          action: { config.audio = false }
        )
        MediaConfigurationChoiceButton(
          title: "On",
          isSelected: config.audio == true,
          action: { config.audio = true }
        )
      }
    }
  }

  private var trayHeight: CGFloat {
    guard let model else { return 94 }
    var sections = 0
    sections += model.aspectRatios.isEmpty ? 0 : 1
    sections += model.resolutions.isEmpty ? 0 : 1
    sections += model.durations?.isEmpty == false ? 1 : 0
    sections += model.outputFormats.isEmpty ? 0 : 1
    sections += model.supportsAudio ? 1 : 0
    return min(300, 78 + CGFloat(sections) * 64)
  }

  @ViewBuilder
  private var trayBackground: some View {
    if theme.usesGlassEffect {
      ZStack {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(.ultraThinMaterial)
        if let overlay = theme.glassOverlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(overlay)
        }
      }
    } else {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(theme.solidBackground)
    }
  }
}

private struct MediaConfigurationChoiceButton: View {
  let title: String
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovered = false
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.appFont(size: 10, weight: isSelected ? .semibold : .medium))
        .foregroundColor(isSelected ? .white : theme.textColor)
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(backgroundColor)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(borderColor, lineWidth: 0.5)
        )
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
  }

  private var backgroundColor: Color {
    if isSelected { return theme.accentColor }
    if isHovered { return theme.textColor.opacity(0.08) }
    return theme.textColor.opacity(0.04)
  }

  private var borderColor: Color {
    isSelected ? theme.accentColor : theme.textColor.opacity(0.1)
  }
}

private struct MediaDurationStepButton: View {
  let systemImage: String
  let isEnabled: Bool
  let action: () -> Void

  @State private var isHovered = false
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.appFont(size: 10, weight: .bold))
        .foregroundColor(isEnabled ? theme.textColor : theme.secondaryTextColor.opacity(0.45))
        .frame(width: 30, height: 30)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isHovered && isEnabled ? theme.textColor.opacity(0.08) : theme.textColor.opacity(0.04))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(theme.textColor.opacity(0.1), lineWidth: 0.5)
        )
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
    .onHover { isHovered = $0 }
  }
}
