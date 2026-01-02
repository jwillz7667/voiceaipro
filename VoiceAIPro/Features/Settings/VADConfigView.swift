import SwiftUI

/// VAD (Voice Activity Detection) configuration view
struct VADConfigView: View {
    @Binding var vadConfig: VADConfig

    // Extract current values for the UI
    private var vadType: VADType {
        switch vadConfig {
        case .serverVAD: return .serverVAD
        case .semanticVAD: return .semanticVAD
        case .disabled: return .disabled
        }
    }

    var body: some View {
        List {
            // VAD Type selection
            Section {
                ForEach(VADType.allCases, id: \.self) { type in
                    VADTypeRow(
                        type: type,
                        isSelected: vadType == type
                    ) {
                        selectVADType(type)
                    }
                }
            } header: {
                Text("Turn Detection Mode")
            } footer: {
                Text(vadType.footerDescription)
            }

            // Semantic VAD options
            if case .semanticVAD(let params) = vadConfig {
                Section {
                    // Eagerness
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Eagerness")
                            .font(.system(size: 16, weight: .medium))

                        GlassSegmentedPicker(
                            options: SemanticVADParams.Eagerness.allCases,
                            selection: Binding(
                                get: { params.eagerness },
                                set: { newValue in
                                    vadConfig = .semanticVAD(SemanticVADParams(
                                        eagerness: newValue,
                                        createResponse: params.createResponse,
                                        interruptResponse: params.interruptResponse
                                    ))
                                }
                            ),
                            label: { $0.displayName }
                        )

                        Text(params.eagerness.description)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)

                    // Auto-create response
                    Toggle(isOn: Binding(
                        get: { params.createResponse },
                        set: { newValue in
                            vadConfig = .semanticVAD(SemanticVADParams(
                                eagerness: params.eagerness,
                                createResponse: newValue,
                                interruptResponse: params.interruptResponse
                            ))
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-create Response")
                                .font(.system(size: 16))
                            Text("Automatically respond after speech")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Allow interruption
                    Toggle(isOn: Binding(
                        get: { params.interruptResponse },
                        set: { newValue in
                            vadConfig = .semanticVAD(SemanticVADParams(
                                eagerness: params.eagerness,
                                createResponse: params.createResponse,
                                interruptResponse: newValue
                            ))
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Allow Interruption")
                                .font(.system(size: 16))
                            Text("User can interrupt AI mid-sentence")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Semantic VAD Settings")
                }
            }

            // Server VAD options
            if case .serverVAD(let params) = vadConfig {
                Section {
                    // Threshold
                    SliderWithLabel(
                        title: "Sensitivity Threshold",
                        value: Binding(
                            get: { params.threshold },
                            set: { newValue in
                                vadConfig = .serverVAD(ServerVADParams(
                                    threshold: newValue,
                                    prefixPaddingMs: params.prefixPaddingMs,
                                    silenceDurationMs: params.silenceDurationMs,
                                    idleTimeoutMs: params.idleTimeoutMs,
                                    createResponse: params.createResponse,
                                    interruptResponse: params.interruptResponse
                                ))
                            }
                        ),
                        range: 0.1...0.9,
                        step: 0.1,
                        description: "Lower = more sensitive to speech"
                    )

                    // Prefix padding
                    IntSliderWithLabel(
                        title: "Prefix Padding",
                        value: Binding(
                            get: { params.prefixPaddingMs },
                            set: { newValue in
                                vadConfig = .serverVAD(ServerVADParams(
                                    threshold: params.threshold,
                                    prefixPaddingMs: newValue,
                                    silenceDurationMs: params.silenceDurationMs,
                                    idleTimeoutMs: params.idleTimeoutMs,
                                    createResponse: params.createResponse,
                                    interruptResponse: params.interruptResponse
                                ))
                            }
                        ),
                        range: 100...1000,
                        step: 50,
                        unit: "ms",
                        description: "Audio included before speech detection"
                    )

                    // Silence duration
                    IntSliderWithLabel(
                        title: "Silence Duration",
                        value: Binding(
                            get: { params.silenceDurationMs },
                            set: { newValue in
                                vadConfig = .serverVAD(ServerVADParams(
                                    threshold: params.threshold,
                                    prefixPaddingMs: params.prefixPaddingMs,
                                    silenceDurationMs: newValue,
                                    idleTimeoutMs: params.idleTimeoutMs,
                                    createResponse: params.createResponse,
                                    interruptResponse: params.interruptResponse
                                ))
                            }
                        ),
                        range: 200...2000,
                        step: 100,
                        unit: "ms",
                        description: "How long to wait before ending turn"
                    )
                } header: {
                    Text("Server VAD Settings")
                }

                Section {
                    // Auto-create response
                    Toggle(isOn: Binding(
                        get: { params.createResponse },
                        set: { newValue in
                            vadConfig = .serverVAD(ServerVADParams(
                                threshold: params.threshold,
                                prefixPaddingMs: params.prefixPaddingMs,
                                silenceDurationMs: params.silenceDurationMs,
                                idleTimeoutMs: params.idleTimeoutMs,
                                createResponse: newValue,
                                interruptResponse: params.interruptResponse
                            ))
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-create Response")
                                .font(.system(size: 16))
                            Text("Automatically respond after speech")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Allow interruption
                    Toggle(isOn: Binding(
                        get: { params.interruptResponse },
                        set: { newValue in
                            vadConfig = .serverVAD(ServerVADParams(
                                threshold: params.threshold,
                                prefixPaddingMs: params.prefixPaddingMs,
                                silenceDurationMs: params.silenceDurationMs,
                                idleTimeoutMs: params.idleTimeoutMs,
                                createResponse: params.createResponse,
                                interruptResponse: newValue
                            ))
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Allow Interruption")
                                .font(.system(size: 16))
                            Text("User can interrupt AI mid-sentence")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Response Behavior")
                }
            }
        }
        .navigationTitle("Turn Detection")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func selectVADType(_ type: VADType) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            switch type {
            case .serverVAD:
                vadConfig = .serverVAD()
            case .semanticVAD:
                vadConfig = .semanticVAD()
            case .disabled:
                vadConfig = .disabled
            }
        }
    }
}

/// VAD type for UI selection
enum VADType: CaseIterable {
    case semanticVAD
    case serverVAD
    case disabled

    var displayName: String {
        switch self {
        case .semanticVAD: return "Semantic VAD"
        case .serverVAD: return "Server VAD"
        case .disabled: return "Manual (Push to Talk)"
        }
    }

    var description: String {
        switch self {
        case .semanticVAD: return "Context-aware, natural turn-taking"
        case .serverVAD: return "Audio-level detection, customizable"
        case .disabled: return "No automatic detection"
        }
    }

    var icon: String {
        switch self {
        case .semanticVAD: return "brain.head.profile"
        case .serverVAD: return "waveform"
        case .disabled: return "hand.tap.fill"
        }
    }

    var footerDescription: String {
        switch self {
        case .semanticVAD:
            return "Uses AI to understand when you've finished speaking. More natural conversation flow."
        case .serverVAD:
            return "Detects speech based on audio levels. More customizable but may interrupt mid-sentence."
        case .disabled:
            return "You control when to send audio. Best for noisy environments."
        }
    }
}

/// VAD type selection row
struct VADTypeRow: View {
    let type: VADType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: type.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.blue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)

                    Text(type.description)
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
        VADConfigView(vadConfig: .constant(.semanticVAD()))
    }
}
