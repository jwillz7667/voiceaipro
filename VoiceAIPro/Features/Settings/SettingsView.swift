import SwiftUI

/// Main settings view with navigation to all configuration options
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                // AI Configuration
                Section {
                    // Voice
                    NavigationLink {
                        VoicePickerView(
                            selectedVoice: $appState.realtimeConfig.voice,
                            voiceSpeed: $appState.realtimeConfig.voiceSpeed
                        )
                    } label: {
                        SettingsRow(
                            icon: "waveform.circle.fill",
                            iconColor: appState.realtimeConfig.voice.color,
                            title: "Voice",
                            value: appState.realtimeConfig.voice.displayName
                        )
                    }

                    // Turn Detection
                    NavigationLink {
                        VADConfigView(vadConfig: $appState.realtimeConfig.vadConfig)
                    } label: {
                        SettingsRow(
                            icon: "mic.badge.waveform",
                            iconColor: .orange,
                            title: "Turn Detection",
                            value: vadTypeName
                        )
                    }

                    // Instructions
                    InstructionsSettingsRow(instructions: $appState.realtimeConfig.instructions)

                    // Advanced
                    NavigationLink {
                        AdvancedSettingsView(config: $appState.realtimeConfig)
                    } label: {
                        SettingsRow(
                            icon: "slider.horizontal.3",
                            iconColor: .purple,
                            title: "Advanced",
                            value: "Temperature, Tokens, Model"
                        )
                    }
                } header: {
                    Text("AI Configuration")
                }

                // Connection Status
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.blue)
                            .frame(width: 28)

                        Text("Server")
                            .font(.system(size: 16))

                        Spacer()

                        HStack(spacing: 6) {
                            Circle()
                                .fill(appState.isServerConnected ? .green : .red)
                                .frame(width: 8, height: 8)
                            Text(appState.isServerConnected ? "Connected" : "Disconnected")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "phone.badge.checkmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.green)
                            .frame(width: 28)

                        Text("Twilio")
                            .font(.system(size: 16))

                        Spacer()

                        HStack(spacing: 6) {
                            Circle()
                                .fill(appState.isTwilioRegistered ? .green : .orange)
                                .frame(width: 8, height: 8)
                            Text(appState.isTwilioRegistered ? "Ready" : "Not Ready")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Connection")
                }

                // About
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.blue)
                            .frame(width: 28)

                        Text("Version")
                            .font(.system(size: 16))

                        Spacer()

                        Text(Constants.App.version)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }

                    Button(action: resetToDefaults) {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.red)
                                .frame(width: 28)

                            Text("Reset to Defaults")
                                .font(.system(size: 16))
                                .foregroundColor(.red)
                        }
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var vadTypeName: String {
        switch appState.realtimeConfig.vadConfig {
        case .serverVAD: return "Server VAD"
        case .semanticVAD: return "Semantic VAD"
        case .disabled: return "Manual"
        }
    }

    private func resetToDefaults() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)

        withAnimation {
            appState.realtimeConfig = RealtimeConfig.default
        }
    }
}

/// Reusable settings row
struct SettingsRow: View {
    let icon: String
    var iconColor: Color = .blue
    let title: String
    var value: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 28)

            Text(title)
                .font(.system(size: 16))

            Spacer()

            if let value = value {
                Text(value)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Quick configuration summary card for dashboard
struct ConfigSummaryCard: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationLink(destination: SettingsView()) {
            GlassCard(padding: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI Configuration")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)

                        Text("Voice: \(appState.realtimeConfig.voice.displayName) • VAD: \(vadTypeName)")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var vadTypeName: String {
        switch appState.realtimeConfig.vadConfig {
        case .serverVAD: return "Server"
        case .semanticVAD: return "Semantic"
        case .disabled: return "Manual"
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
