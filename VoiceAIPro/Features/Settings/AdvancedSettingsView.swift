import SwiftUI

/// Advanced AI settings: temperature, tokens, model, noise reduction, transcription
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
                Text(config.model == .gptRealtime
                    ? "Full-featured model for complex conversations"
                    : "Faster, lighter model for simple tasks")
            }

            // Temperature
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Temperature")
                            .font(.system(size: 16, weight: .medium))

                        Spacer()

                        Text(String(format: "%.1f", config.temperature))
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
                        Text("Predictable")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        Slider(value: $config.temperature, in: 0.6...1.2, step: 0.1)
                            .tint(.blue)
                            .onChange(of: config.temperature) { _, _ in
                                let generator = UISelectionFeedbackGenerator()
                                generator.selectionChanged()
                            }

                        Text("Creative")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Response Style")
            } footer: {
                Text("Higher values make responses more varied and creative")
            }

            // Max tokens
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Max Response Length")
                            .font(.system(size: 16, weight: .medium))

                        Spacer()

                        Text(tokenDisplayValue)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.blue.opacity(0.12))
                            )
                    }

                    Slider(
                        value: Binding(
                            get: { Double(config.maxOutputTokens) },
                            set: { config.maxOutputTokens = Int($0) }
                        ),
                        in: 256...8192,
                        step: 256
                    )
                    .tint(.blue)
                    .onChange(of: config.maxOutputTokens) { _, _ in
                        let generator = UISelectionFeedbackGenerator()
                        generator.selectionChanged()
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Response Length")
            } footer: {
                Text("Maximum number of tokens in AI responses")
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

    private var tokenDisplayValue: String {
        if config.maxOutputTokens >= 8192 {
            return "Max"
        }
        return "\(config.maxOutputTokens)"
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
                Image(systemName: model == .gptRealtime ? "cpu.fill" : "bolt.fill")
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
                Image(systemName: model == .whisper1 ? "hare.fill" : "brain.head.profile")
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

// MARK: - Model Extensions

extension RealtimeModel {
    var displayName: String {
        switch self {
        case .gptRealtime: return "GPT Realtime"
        case .gptRealtimeMini: return "GPT Realtime Mini"
        }
    }

    var description: String {
        switch self {
        case .gptRealtime: return "Full-featured, complex conversations"
        case .gptRealtimeMini: return "Faster, simpler responses"
        }
    }
}

extension TranscriptionModel {
    var displayName: String {
        switch self {
        case .whisper1: return "Whisper-1"
        case .gpt4oTranscribe: return "GPT-4o Transcribe"
        }
    }

    var description: String {
        switch self {
        case .whisper1: return "Fast, reliable transcription"
        case .gpt4oTranscribe: return "More accurate, context-aware"
        }
    }
}

#Preview {
    NavigationStack {
        AdvancedSettingsView(config: .constant(RealtimeConfig.default))
    }
}
