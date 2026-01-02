import SwiftUI

/// Glass-styled segmented picker
struct GlassSegmentedPicker<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String
    var icon: ((T) -> String)? = nil

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selection = option
                    }
                }) {
                    HStack(spacing: 6) {
                        if let icon = icon?(option) {
                            Image(systemName: icon)
                                .font(.system(size: 12, weight: .medium))
                        }
                        Text(label(option))
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(selection == option ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        ZStack {
                            if selection == option {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.blue)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }
}

/// Labeled segmented picker row
struct SegmentedPickerRow<T: Hashable>: View {
    let title: String
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String
    var icon: String? = nil
    var description: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.blue)
                        .frame(width: 24)
                }

                Text(title)
                    .font(.system(size: 16, weight: .medium))
            }

            GlassSegmentedPicker(
                options: options,
                selection: $selection,
                label: label
            )

            if let description = description {
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// Radio button list for single selection
struct RadioButtonList<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String
    var subtitle: ((T) -> String?)? = nil
    var icon: ((T) -> String)? = nil
    var color: ((T) -> Color)? = nil

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        selection = option
                    }
                }) {
                    HStack(spacing: 12) {
                        // Color indicator or icon
                        if let color = color?(option) {
                            Circle()
                                .fill(color)
                                .frame(width: 12, height: 12)
                        } else if let icon = icon?(option) {
                            Image(systemName: icon)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.blue)
                                .frame(width: 24)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(label(option))
                                .font(.system(size: 16))
                                .foregroundColor(.primary)

                            if let subtitle = subtitle?(option) {
                                Text(subtitle)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        // Radio button indicator
                        ZStack {
                            Circle()
                                .stroke(selection == option ? Color.blue : Color.secondary.opacity(0.3), lineWidth: 2)
                                .frame(width: 22, height: 22)

                            if selection == option {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 12, height: 12)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < options.count - 1 {
                    Divider()
                        .padding(.leading, icon != nil || color != nil ? 36 : 0)
                }
            }
        }
    }
}

/// Dropdown picker with glass styling
struct GlassDropdownPicker<T: Hashable>: View {
    let title: String
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                    .frame(width: 24)
            }

            Text(title)
                .font(.system(size: 16, weight: .medium))

            Spacer()

            Menu {
                ForEach(options, id: \.self) { option in
                    Button(action: {
                        selection = option
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                    }) {
                        HStack {
                            Text(label(option))
                            if selection == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(label(selection))
                        .font(.system(size: 15, weight: .medium))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.12))
                )
            }
        }
    }
}

// MARK: - Preview Helpers

private enum PreviewEagerness: String, CaseIterable {
    case low, medium, high, auto
}

private enum PreviewVoice: String, CaseIterable {
    case marin, cedar, alloy, echo
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()

        ScrollView {
            VStack(spacing: 20) {
                GlassCard {
                    SegmentedPickerRow(
                        title: "Eagerness",
                        options: PreviewEagerness.allCases,
                        selection: .constant(.high),
                        label: { $0.rawValue.capitalized },
                        icon: "gauge.with.needle",
                        description: "How quickly AI responds to pauses"
                    )
                }

                GlassCard {
                    RadioButtonList(
                        options: PreviewVoice.allCases,
                        selection: .constant(.marin),
                        label: { $0.rawValue.capitalized },
                        subtitle: { voice in
                            switch voice {
                            case .marin: return "Professional, clear"
                            case .cedar: return "Natural, conversational"
                            case .alloy: return "Neutral, balanced"
                            case .echo: return "Warm, engaging"
                            }
                        },
                        color: { voice in
                            switch voice {
                            case .marin: return .blue
                            case .cedar: return .green
                            case .alloy: return .gray
                            case .echo: return .orange
                            }
                        }
                    )
                }

                GlassCard {
                    GlassDropdownPicker(
                        title: "VAD Type",
                        options: ["Server VAD", "Semantic VAD", "Disabled"],
                        selection: .constant("Semantic VAD"),
                        label: { $0 },
                        icon: "waveform"
                    )
                }
            }
            .padding()
        }
    }
}
