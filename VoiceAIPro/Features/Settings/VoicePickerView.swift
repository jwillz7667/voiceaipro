import SwiftUI

/// Voice selection view with all 10 OpenAI Realtime voices
struct VoicePickerView: View {
    @Binding var selectedVoice: RealtimeVoice
    @Binding var voiceSpeed: Double

    var body: some View {
        List {
            // Voice selection section
            Section {
                ForEach(RealtimeVoice.allCases, id: \.self) { voice in
                    VoiceRow(
                        voice: voice,
                        isSelected: selectedVoice == voice
                    ) {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selectedVoice = voice
                        }
                    }
                }
            } header: {
                Text("Select Voice")
            } footer: {
                Text("Marin and Cedar are recommended for professional use")
            }

            // Voice speed section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Voice Speed")
                            .font(.system(size: 16, weight: .medium))

                        Spacer()

                        Text(String(format: "%.1fx", voiceSpeed))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.blue.opacity(0.12))
                            )
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "tortoise.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)

                        Slider(value: $voiceSpeed, in: 0.5...1.5, step: 0.1)
                            .tint(.blue)
                            .onChange(of: voiceSpeed) { _, _ in
                                let generator = UISelectionFeedbackGenerator()
                                generator.selectionChanged()
                            }

                        Image(systemName: "hare.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Playback Speed")
            } footer: {
                Text("Adjust how fast the AI speaks")
            }
        }
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Individual voice row
struct VoiceRow: View {
    let voice: RealtimeVoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Color indicator
                Circle()
                    .fill(voice.color)
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(voice.displayName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)

                        if voice.isRecommended {
                            Text("Recommended")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.blue)
                                )
                        }
                    }

                    Text(voice.voiceDescription)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.blue)
                } else {
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 22, height: 22)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Voice Extensions

extension RealtimeVoice {
    var displayName: String {
        rawValue.capitalized
    }

    var voiceDescription: String {
        switch self {
        case .marin: return "Professional, clear - Best for assistants"
        case .cedar: return "Natural, conversational - Best for support"
        case .alloy: return "Neutral, balanced - General purpose"
        case .echo: return "Warm, engaging - Customer service"
        case .shimmer: return "Energetic, expressive - Sales"
        case .ash: return "Confident, assertive - Business"
        case .ballad: return "Storytelling tone - Narratives"
        case .coral: return "Friendly, approachable - Casual"
        case .sage: return "Wise, thoughtful - Advisory"
        case .verse: return "Dramatic, expressive - Creative"
        }
    }

    var isRecommended: Bool {
        self == .marin || self == .cedar
    }

    var color: Color {
        switch self {
        case .marin: return .blue
        case .cedar: return .green
        case .alloy: return .gray
        case .echo: return .orange
        case .shimmer: return .pink
        case .ash: return .brown
        case .ballad: return .purple
        case .coral: return .red
        case .sage: return .mint
        case .verse: return .indigo
        }
    }
}

#Preview {
    NavigationStack {
        VoicePickerView(
            selectedVoice: .constant(.marin),
            voiceSpeed: .constant(1.0)
        )
    }
}
