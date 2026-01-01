import SwiftUI
import SwiftData

/// Main content view with tab navigation
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DIContainer
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab: Tab = .dashboard

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                DashboardTab()
                    .tabItem {
                        Label("Dashboard", systemImage: "house.fill")
                    }
                    .tag(Tab.dashboard)

                DialerTab()
                    .tabItem {
                        Label("Dialer", systemImage: "phone.fill")
                    }
                    .tag(Tab.dialer)

                HistoryTab()
                    .tabItem {
                        Label("History", systemImage: "clock.fill")
                    }
                    .tag(Tab.history)

                RecordingsTab()
                    .tabItem {
                        Label("Recordings", systemImage: "waveform")
                    }
                    .tag(Tab.recordings)

                SettingsTab()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(Tab.settings)
            }
            .tint(.voiceAIPrimary)

            // Active call overlay
            if appState.isCallActive {
                ActiveCallOverlay()
            }

            // Event log overlay
            if appState.showEventLog {
                EventLogOverlay()
            }
        }
        .alert(item: $appState.activeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK")) {
                    appState.dismissAlert()
                }
            )
        }
        .onAppear {
            setupInitialState()
        }
    }

    private func setupInitialState() {
        // Load saved prompts into app state if needed
        // Connect to server if auto-connect is enabled
    }
}

// MARK: - Tab Enum

enum Tab: String, CaseIterable {
    case dashboard
    case dialer
    case history
    case recordings
    case settings
}

// MARK: - Tab Views

struct DashboardTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Connection Status
                    ConnectionStatusCard()

                    // Quick Actions
                    QuickActionsCard()

                    // Recent Calls
                    RecentCallsCard()
                }
                .padding()
            }
            .navigationTitle("VoiceAI Pro")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        appState.showEventLog.toggle()
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                }
            }
        }
    }
}

struct DialerTab: View {
    @EnvironmentObject var appState: AppState
    @State private var phoneNumber: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Phone number display
                Text(phoneNumber.isEmpty ? "Enter Phone Number" : phoneNumber.formattedPhoneNumber)
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .foregroundColor(phoneNumber.isEmpty ? .secondary : .primary)

                // Dial pad
                DialPadView(phoneNumber: $phoneNumber)

                // Call button
                Button {
                    if phoneNumber.isValidPhoneNumber {
                        appState.startCall(to: phoneNumber)
                    }
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 28))
                }
                .callButtonStyle()
                .disabled(!phoneNumber.isValidPhoneNumber)
                .opacity(phoneNumber.isValidPhoneNumber ? 1 : 0.5)

                Spacer()
            }
            .padding()
            .navigationTitle("Dialer")
        }
    }
}

struct HistoryTab: View {
    @Query(sort: \CallRecord.startedAt, order: .reverse)
    private var callRecords: [CallRecord]

    var body: some View {
        NavigationStack {
            List {
                if callRecords.isEmpty {
                    ContentUnavailableView(
                        "No Call History",
                        systemImage: "phone.badge.plus",
                        description: Text("Your call history will appear here")
                    )
                } else {
                    ForEach(callRecords) { record in
                        CallHistoryRow(record: record)
                    }
                }
            }
            .navigationTitle("History")
        }
    }
}

struct RecordingsTab: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Recordings",
                systemImage: "waveform",
                description: Text("Call recordings will appear here")
            )
            .navigationTitle("Recordings")
        }
    }
}

struct SettingsTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                Section("AI Configuration") {
                    NavigationLink {
                        VoiceSelectionView()
                    } label: {
                        Label("Voice", systemImage: "speaker.wave.2")
                    }

                    NavigationLink {
                        VADConfigView()
                    } label: {
                        Label("Turn Detection", systemImage: "waveform")
                    }

                    NavigationLink {
                        PromptsListView()
                    } label: {
                        Label("Prompts", systemImage: "text.bubble")
                    }
                }

                Section("Connection") {
                    HStack {
                        Label("Server Status", systemImage: appState.connectionState.icon)
                        Spacer()
                        Text(appState.connectionState.displayName)
                            .foregroundColor(appState.connectionState.color)
                    }

                    HStack {
                        Label("Twilio", systemImage: "phone.circle")
                        Spacer()
                        Text(appState.isTwilioRegistered ? "Registered" : "Not Registered")
                            .foregroundColor(appState.isTwilioRegistered ? .green : .secondary)
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Supporting Views

struct ConnectionStatusCard: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: appState.connectionState.icon)
                .font(.title2)
                .foregroundColor(appState.connectionState.color)

            VStack(alignment: .leading, spacing: 4) {
                Text(appState.connectionState.displayName)
                    .font(.headline)
                Text(appState.isTwilioRegistered ? "Ready to call" : "Connecting...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .cardStyle()
    }
}

struct QuickActionsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            HStack(spacing: 16) {
                QuickActionButton(icon: "phone.fill", title: "New Call", color: .voiceAISuccess) {
                    // Navigate to dialer
                }

                QuickActionButton(icon: "text.bubble", title: "Prompts", color: .voiceAIPrimary) {
                    // Navigate to prompts
                }

                QuickActionButton(icon: "gearshape", title: "Settings", color: .voiceAISecondary) {
                    // Navigate to settings
                }
            }
        }
        .padding()
        .cardStyle()
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(color.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

struct RecentCallsCard: View {
    @Query(CallRecord.recentCalls(limit: 5))
    private var recentCalls: [CallRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Calls")
                .font(.headline)

            if recentCalls.isEmpty {
                Text("No recent calls")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
            } else {
                ForEach(recentCalls) { record in
                    HStack {
                        Image(systemName: record.callDirection.icon)
                            .foregroundColor(record.callStatus == .failed ? .red : .primary)

                        VStack(alignment: .leading) {
                            Text(record.formattedPhoneNumber)
                                .font(.subheadline)
                            Text(record.formattedStartTime)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text(record.formattedDuration)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .cardStyle()
    }
}

struct DialPadView: View {
    @Binding var phoneNumber: String

    let keys = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["*", "0", "#"]
    ]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 20) {
                    ForEach(row, id: \.self) { key in
                        DialKey(key: key) {
                            phoneNumber.append(key)
                        }
                    }
                }
            }

            HStack(spacing: 20) {
                DialKey(key: "", label: "") { }
                    .opacity(0)

                DialKey(key: "+", label: "+") {
                    if phoneNumber.isEmpty {
                        phoneNumber = "+"
                    }
                }

                Button {
                    if !phoneNumber.isEmpty {
                        phoneNumber.removeLast()
                    }
                } label: {
                    Image(systemName: "delete.left")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .frame(width: 72, height: 72)
                }
            }
        }
    }
}

struct DialKey: View {
    let key: String
    var label: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label ?? key)
                .font(.system(size: 28, weight: .medium))
                .frame(width: 72, height: 72)
                .background(Color.voiceAISurface)
                .clipShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct CallHistoryRow: View {
    let record: CallRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.callDirection.icon)
                .foregroundColor(record.callStatus == .failed ? .red : .voiceAIPrimary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.formattedPhoneNumber)
                    .font(.body)
                HStack {
                    Text(record.callDirection.displayName)
                    Text("•")
                    Text(record.formattedStartTime)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            Text(record.formattedDuration)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

struct ActiveCallOverlay: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 16) {
                Text(appState.currentCall?.formattedPhoneNumber ?? "Unknown")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(appState.callStatus.displayName)
                    .foregroundColor(.secondary)

                Text(appState.currentCall?.formattedDuration ?? "00:00")
                    .font(.system(size: 48, weight: .light, design: .monospaced))

                HStack(spacing: 40) {
                    CallControlButton(icon: appState.isMuted ? "mic.slash.fill" : "mic.fill",
                                    isActive: appState.isMuted) {
                        appState.isMuted.toggle()
                    }

                    Button {
                        appState.endCall()
                    } label: {
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 24))
                    }
                    .callButtonStyle(isActive: true)

                    CallControlButton(icon: appState.isSpeakerEnabled ? "speaker.wave.2.fill" : "speaker.fill",
                                    isActive: appState.isSpeakerEnabled) {
                        appState.isSpeakerEnabled.toggle()
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .cornerRadius(24)
            .padding()
        }
        .background(Color.black.opacity(0.5).ignoresSafeArea())
    }
}

struct CallControlButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(isActive ? .white : .primary)
                .frame(width: 56, height: 56)
                .background(isActive ? Color.voiceAIPrimary : Color.voiceAISurface)
                .clipShape(Circle())
        }
    }
}

struct EventLogOverlay: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack {
            HStack {
                Text("Event Log")
                    .font(.headline)
                Spacer()
                Button {
                    appState.showEventLog = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()

            List(appState.events) { event in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: event.eventType.icon)
                            .foregroundColor(.voiceAIPrimary)
                        Text(event.eventType.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text(event.formattedTimestamp)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(event.shortDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .padding()
    }
}

// MARK: - Settings Views

struct VoiceSelectionView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List {
            ForEach(RealtimeVoice.allCases) { voice in
                Button {
                    appState.realtimeConfig.voice = voice
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(voice.displayName)
                                .foregroundColor(.primary)
                            Text(voice.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if appState.realtimeConfig.voice == voice {
                            Image(systemName: "checkmark")
                                .foregroundColor(.voiceAIPrimary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Voice")
    }
}

struct VADConfigView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List {
            Section("Turn Detection Mode") {
                VADOptionRow(title: "Server VAD", description: "Audio-level voice detection", isSelected: isServerVAD) {
                    appState.realtimeConfig.vadConfig = .serverVAD()
                }

                VADOptionRow(title: "Semantic VAD", description: "Context-aware detection", isSelected: isSemanticVAD) {
                    appState.realtimeConfig.vadConfig = .semanticVAD()
                }

                VADOptionRow(title: "Disabled", description: "Manual control", isSelected: isDisabled) {
                    appState.realtimeConfig.vadConfig = .disabled
                }
            }
        }
        .navigationTitle("Turn Detection")
    }

    var isServerVAD: Bool {
        if case .serverVAD = appState.realtimeConfig.vadConfig { return true }
        return false
    }

    var isSemanticVAD: Bool {
        if case .semanticVAD = appState.realtimeConfig.vadConfig { return true }
        return false
    }

    var isDisabled: Bool {
        if case .disabled = appState.realtimeConfig.vadConfig { return true }
        return false
    }
}

struct VADOptionRow: View {
    let title: String
    let description: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading) {
                    Text(title)
                        .foregroundColor(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.voiceAIPrimary)
                }
            }
        }
    }
}

struct PromptsListView: View {
    @Query(SavedPrompt.allPrompts())
    private var prompts: [SavedPrompt]

    var body: some View {
        List {
            ForEach(prompts) { prompt in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(prompt.name)
                            .fontWeight(.medium)
                        if prompt.isDefault {
                            Text("Default")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.voiceAIPrimary.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                    Text(prompt.instructionsPreview)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .navigationTitle("Prompts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // Add new prompt
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(DIContainer.shared)
        .modelContainer(for: [CallRecord.self, SavedPrompt.self, EventLogEntry.self], inMemory: true)
}
