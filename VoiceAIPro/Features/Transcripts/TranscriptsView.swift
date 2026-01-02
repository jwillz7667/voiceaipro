import SwiftUI
import SwiftData

/// View showing all saved transcripts grouped by call
struct TranscriptsView: View {
    @Query(sort: \CallRecord.startedAt, order: .reverse) private var calls: [CallRecord]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedCall: CallRecord?
    @State private var searchText = ""

    private var callsWithTranscripts: [CallRecord] {
        calls.filter { call in
            guard let callSid = call.callSid else { return false }
            let descriptor = TranscriptEntry.transcripts(forCallSid: callSid)
            let transcripts = (try? modelContext.fetch(descriptor)) ?? []
            return !transcripts.isEmpty
        }
    }

    private var filteredCalls: [CallRecord] {
        if searchText.isEmpty {
            return callsWithTranscripts
        }
        return callsWithTranscripts.filter { call in
            call.phoneNumber.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if callsWithTranscripts.isEmpty {
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
                }
            }
            .navigationTitle("Transcripts")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $selectedCall) { call in
                TranscriptDetailView(call: call)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Transcripts Yet",
            systemImage: "text.bubble",
            description: Text("Transcripts from your calls will appear here")
        )
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

                    // Transcripts
                    if transcripts.isEmpty {
                        Text("No transcripts available")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    } else {
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
            .onAppear {
                loadTranscripts()
            }
        }
    }

    private func loadTranscripts() {
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
