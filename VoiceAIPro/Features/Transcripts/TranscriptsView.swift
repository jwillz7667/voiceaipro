import SwiftUI
import SwiftData

/// View showing all saved transcripts grouped by call
struct TranscriptsView: View {
    @Query(sort: \CallRecord.startedAt, order: .reverse) private var calls: [CallRecord]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedCall: CallRecord?
    @State private var searchText = ""
    @State private var isRefreshing = false

    /// All calls - we'll show all completed calls and let user tap to load transcripts
    private var completedCalls: [CallRecord] {
        calls.filter { $0.callSid != nil && $0.status == "completed" }
    }

    private var filteredCalls: [CallRecord] {
        if searchText.isEmpty {
            return completedCalls
        }
        return completedCalls.filter { call in
            call.phoneNumber.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if completedCalls.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(filteredCalls) { call in
                            TranscriptCallRow(call: call)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedCall = call
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .searchable(text: $searchText, prompt: "Search calls")
                    .refreshable {
                        await refreshCallHistory()
                    }
                }
            }
            .navigationTitle("Transcripts")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $selectedCall) { call in
                TranscriptDetailView(call: call)
            }
            .task {
                await refreshCallHistory()
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Calls Yet",
            systemImage: "text.bubble",
            description: Text("Complete a call to see transcripts here")
        )
    }

    /// Refresh call history from server
    private func refreshCallHistory() async {
        guard !isRefreshing else { return }
        isRefreshing = true

        do {
            // APIClientProtocol returns [[String: Any]]
            let serverCalls = try await DIContainer.shared.apiClient.getCallHistory(limit: 50, offset: 0)

            await MainActor.run {
                for callData in serverCalls {
                    // Parse the dictionary to CallHistoryItem
                    guard let item = CallHistoryItem(from: callData) else { continue }

                    let serverCallSid = item.callSid

                    // Check if call already exists locally
                    let descriptor = FetchDescriptor<CallRecord>(
                        predicate: #Predicate { record in
                            record.callSid == serverCallSid
                        }
                    )
                    let existing = try? modelContext.fetch(descriptor)

                    if existing?.isEmpty ?? true {
                        // Use convenience initializer which handles all fields
                        let record = CallRecord(from: item)
                        modelContext.insert(record)
                    }
                }

                try? modelContext.save()
                isRefreshing = false
            }
        } catch {
            await MainActor.run {
                isRefreshing = false
            }
        }
    }
}

/// Row showing a call with transcript summary
struct TranscriptCallRow: View {
    let call: CallRecord
    @Environment(\.modelContext) private var modelContext

    private var transcriptCount: Int {
        guard let callSid = call.callSid else { return 0 }
        let descriptor = TranscriptEntry.transcripts(forCallSid: callSid)
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    private var transcriptPreview: String {
        guard let callSid = call.callSid else { return "" }
        var descriptor = TranscriptEntry.transcripts(forCallSid: callSid)
        descriptor.fetchLimit = 1
        if let first = try? modelContext.fetch(descriptor).first {
            return first.contentPreview
        }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Direction icon
                Image(systemName: call.callDirection == .outbound ? "phone.arrow.up.right" : "phone.arrow.down.left")
                    .font(.system(size: 14))
                    .foregroundColor(call.callDirection == .outbound ? .blue : .green)

                Text(formattedPhoneNumber)
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                Text(formattedDate)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            if !transcriptPreview.isEmpty {
                Text(transcriptPreview)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            HStack {
                Label("\(transcriptCount) entries", systemImage: "text.bubble")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Spacer()

                if let duration = call.durationSeconds, duration > 0 {
                    Text(formattedDuration(duration))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var formattedPhoneNumber: String {
        let digits = call.phoneNumber.filter { $0.isNumber }
        guard digits.count >= 10 else { return call.phoneNumber }

        if digits.count == 10 {
            let areaCode = String(digits.prefix(3))
            let middle = String(digits.dropFirst(3).prefix(3))
            let last = String(digits.dropFirst(6))
            return "(\(areaCode)) \(middle)-\(last)"
        }
        return call.phoneNumber
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(call.startedAt) {
            formatter.dateFormat = "h:mm a"
        } else if calendar.isDateInYesterday(call.startedAt) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: call.startedAt)
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }
        return "\(secs)s"
    }
}

/// Detailed transcript view for a specific call
struct TranscriptDetailView: View {
    let call: CallRecord
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var transcripts: [TranscriptEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Call info header
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formattedPhoneNumber)
                            .font(.title2.bold())

                        HStack {
                            Image(systemName: call.callDirection == .outbound ? "phone.arrow.up.right" : "phone.arrow.down.left")
                                .foregroundColor(call.callDirection == .outbound ? .blue : .green)
                            Text(call.callDirection.displayName)
                            Text("•")
                            Text(formattedDateTime)
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)

                    Divider()

                    // Loading state
                    if isLoading {
                        ProgressView("Loading transcripts...")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    }
                    // Error state
                    else if let error = errorMessage {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.orange)
                            Text(error)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Retry") {
                                Task { await fetchTranscripts() }
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                    }
                    // Empty state
                    else if transcripts.isEmpty {
                        Text("No transcripts available")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    }
                    // Transcripts list
                    else {
                        ForEach(transcripts) { transcript in
                            TranscriptBubbleView(transcript: transcript)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }

                ToolbarItem(placement: .topBarLeading) {
                    if !transcripts.isEmpty {
                        ShareLink(
                            item: formattedTranscriptText,
                            subject: Text("Call Transcript"),
                            message: Text("Transcript from call with \(formattedPhoneNumber)")
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .task {
                await fetchTranscripts()
            }
        }
    }

    /// Fetch transcripts from server and save to local SwiftData
    private func fetchTranscripts() async {
        guard let callSid = call.callSid else {
            errorMessage = "No call ID available"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            // Fetch full call details which includes transcripts
            let response = try await DIContainer.shared.apiClient.getFullCallDetails(callSid: callSid)

            // Convert and save to SwiftData
            await MainActor.run {
                if let serverTranscripts = response.transcripts {
                    for serverTranscript in serverTranscripts {
                        let transcriptId = serverTranscript.id

                        // Check if already exists
                        let descriptor = FetchDescriptor<TranscriptEntry>(
                            predicate: #Predicate { entry in
                                entry.id == transcriptId
                            }
                        )
                        let existing = try? modelContext.fetch(descriptor)

                        if existing?.isEmpty ?? true {
                            // Create new entry
                            let entry = serverTranscript.toTranscriptEntry(callSid: callSid)
                            modelContext.insert(entry)
                        }
                    }

                    // Save context
                    try? modelContext.save()
                }

                // Load from local storage (now populated)
                loadLocalTranscripts()
                isLoading = false
            }
        } catch {
            await MainActor.run {
                // Try loading from local cache on error
                loadLocalTranscripts()
                if transcripts.isEmpty {
                    errorMessage = "Failed to load transcripts: \(error.localizedDescription)"
                }
                isLoading = false
            }
        }
    }

    /// Load transcripts from local SwiftData
    private func loadLocalTranscripts() {
        guard let callSid = call.callSid else { return }
        let descriptor = TranscriptEntry.transcripts(forCallSid: callSid)
        transcripts = (try? modelContext.fetch(descriptor)) ?? []
    }

    private var formattedPhoneNumber: String {
        let digits = call.phoneNumber.filter { $0.isNumber }
        guard digits.count >= 10 else { return call.phoneNumber }
        if digits.count == 10 {
            let areaCode = String(digits.prefix(3))
            let middle = String(digits.dropFirst(3).prefix(3))
            let last = String(digits.dropFirst(6))
            return "(\(areaCode)) \(middle)-\(last)"
        }
        return call.phoneNumber
    }

    private var formattedDateTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: call.startedAt)
    }

    private var formattedTranscriptText: String {
        var text = "Call Transcript - \(formattedPhoneNumber)\n"
        text += "Date: \(formattedDateTime)\n\n"
        for transcript in transcripts {
            text += "[\(transcript.formattedTimestamp)] \(transcript.speakerDisplayName):\n"
            text += "\(transcript.content)\n\n"
        }
        return text
    }
}

/// Bubble view for individual transcript entry
struct TranscriptBubbleView: View {
    let transcript: TranscriptEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(transcript.isUser ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: transcript.isUser ? "person.fill" : "sparkles")
                    .font(.system(size: 14))
                    .foregroundColor(transcript.isUser ? .green : .blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(transcript.speakerDisplayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(transcript.isUser ? .green : .blue)

                    Spacer()

                    Text(transcript.formattedTimestamp)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Text(transcript.content)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

#Preview {
    TranscriptsView()
        .modelContainer(for: [CallRecord.self, TranscriptEntry.self], inMemory: true)
}
