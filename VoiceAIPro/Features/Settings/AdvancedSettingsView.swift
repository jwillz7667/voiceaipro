import SwiftUI

/// Advanced AI settings: model, noise reduction, transcription
/// NOTE: temperature and maxOutputTokens removed for OpenAI Realtime API GA compliance
struct AdvancedSettingsView: View {
    @Binding var config: RealtimeConfig

    var body: some View {
        List {
            // Model selection
            Section {
                ForEach(RealtimeModel.allCases, id: \.self) { model in
                    ModelRow(
                        model: model,
                        isSelected: config.model == model
                    ) {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        config.model = model
                    }
                }
            } header: {
                Text("Model")
            } footer: {
                Text(config.model == .gptRealtime1_5
                    ? "Full-featured model for complex conversations"
                    : "Faster, lighter model for simple tasks")
            }

            // Noise reduction
            Section {
                ForEach(NoiseReductionOption.allCases, id: \.self) { option in
                    NoiseReductionRow(
                        option: option,
                        isSelected: currentNoiseReduction == option
                    ) {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        config.noiseReduction = option.value
                    }
                }
            } header: {
                Text("Noise Reduction")
            } footer: {
                Text(noiseReductionFooter)
            }

            // Transcription model
            Section {
                ForEach(TranscriptionModel.allCases, id: \.self) { model in
                    TranscriptionRow(
                        model: model,
                        isSelected: config.transcriptionModel == model
                    ) {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        config.transcriptionModel = model
                    }
                }
            } header: {
                Text("Transcription")
            } footer: {
                Text("Model used for converting speech to text")
            }
        }
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var currentNoiseReduction: NoiseReductionOption {
        guard let nr = config.noiseReduction else { return .none }
        switch nr {
        case .nearField: return .nearField
        case .farField: return .farField
        }
    }

    private var noiseReductionFooter: String {
        switch currentNoiseReduction {
        case .none:
            return "No audio preprocessing applied"
        case .nearField:
            return "Optimized for close microphone (phone to ear)"
        case .farField:
            return "Optimized for distant microphone (speakerphone)"
        }
    }
}

/// Noise reduction option for UI
enum NoiseReductionOption: CaseIterable {
    case none
    case nearField
    case farField

    var displayName: String {
        switch self {
        case .none: return "None"
        case .nearField: return "Near Field"
        case .farField: return "Far Field"
        }
    }

    var description: String {
        switch self {
        case .none: return "No noise reduction"
        case .nearField: return "Phone to ear"
        case .farField: return "Speakerphone"
        }
    }

    var icon: String {
        switch self {
        case .none: return "waveform"
        case .nearField: return "iphone"
        case .farField: return "speaker.wave.3.fill"
        }
    }

    var value: NoiseReduction? {
        switch self {
        case .none: return nil
        case .nearField: return .nearField
        case .farField: return .farField
        }
    }
}

/// Model selection row
struct ModelRow: View {
    let model: RealtimeModel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: model == .gptRealtime1_5 ? "cpu.fill" : "bolt.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.blue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)

                    Text(model.description)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Spacer()

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

/// Noise reduction row
struct NoiseReductionRow: View {
    let option: NoiseReductionOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: option.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.blue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.displayName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)

                    Text(option.description)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Spacer()

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

/// Transcription model row
struct TranscriptionRow: View {
    let model: TranscriptionModel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: model == .gpt4oMiniTranscribe ? "hare.fill" : "brain.head.profile")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.blue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)

                    Text(model.description)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Spacer()

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

#Preview {
    NavigationStack {
        AdvancedSettingsView(config: .constant(RealtimeConfig.default))
    }
}
