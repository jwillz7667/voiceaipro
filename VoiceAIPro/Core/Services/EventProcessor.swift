import Foundation
import Combine

/// Processes and manages real-time events from calls
@MainActor
class EventProcessor: ObservableObject {
    // MARK: - Published Properties

    /// All events (limited to maxEvents)
    @Published private(set) var events: [CallEvent] = []

    /// Current combined transcript
    @Published private(set) var currentTranscript: String = ""

    /// User transcript only
    @Published private(set) var userTranscript: String = ""

    /// AI transcript only
    @Published private(set) var aiTranscript: String = ""

    /// Whether AI is currently speaking
    @Published private(set) var isAISpeaking: Bool = false

    /// Whether user is currently speaking
    @Published private(set) var isUserSpeaking: Bool = false

    /// Current AI response text (streaming)
    @Published private(set) var currentAIResponse: String = ""

    /// Current user speech text (streaming)
    @Published private(set) var currentUserSpeech: String = ""

    /// Last error event
    @Published private(set) var lastError: CallEvent?

    /// Function calls detected
    @Published private(set) var functionCalls: [FunctionCallEvent] = []

    // MARK: - Configuration

    /// Maximum events to retain
    private let maxEvents: Int

    /// Current call ID
    private var currentCallId: String?

    // MARK: - Callbacks

    /// Called when transcript is updated
    var onTranscriptUpdate: ((String, String) -> Void)? // (user, ai)

    /// Called when error occurs
    var onError: ((CallEvent) -> Void)?

    /// Called when function is called
    var onFunctionCall: ((FunctionCallEvent) -> Void)?

    // MARK: - Initialization

    init(maxEvents: Int = 1000) {
        self.maxEvents = maxEvents
    }

    // MARK: - Event Processing

    /// Process an incoming event
    func processEvent(_ event: CallEvent) {
        print("🟣 [EventProcessor] ========== PROCESS EVENT ==========")
        print("🟣 [EventProcessor] Event type: \(event.eventType.rawValue)")
        print("🟣 [EventProcessor] Event display: \(event.eventType.displayName)")
        print("🟣 [EventProcessor] Call ID: \(event.callId)")
        print("🟣 [EventProcessor] Payload preview: \(String(event.payload?.prefix(200) ?? "nil"))")

        // Add to events list with limit
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }

        // Update state based on event type
        switch event.eventType {
        // Session events
        case .sessionCreated, .sessionUpdated:
            handleSessionEvent(event)

        // Speech events
        case .speechStarted:
            isUserSpeaking = true

        case .speechStopped:
            isUserSpeaking = false

        // Transcription events
        case .transcriptionCompleted:
            handleTranscriptionCompleted(event)

        // AI Response events
        case .responseCreated:
            currentAIResponse = ""

        case .responseTextDelta:
            handleTextDelta(event)

        case .responseTextDone:
            handleTextDone(event)

        case .responseAudioDelta:
            isAISpeaking = true

        case .responseAudioDone:
            isAISpeaking = false

        case .responseDone:
            handleResponseDone(event)

        // Function calls
        case .responseFunctionCallArgumentsDelta:
            handleFunctionCallDelta(event)

        case .responseFunctionCallArgumentsDone:
            handleFunctionCallDone(event)

        // Audio buffer events
        case .audioBufferCommitted:
            // Audio was committed for processing
            break

        case .audioBufferCleared:
            currentUserSpeech = ""

        // Conversation events
        case .conversationItemCreated:
            handleConversationItemCreated(event)

        case .conversationItemDeleted:
            handleConversationItemDeleted(event)

        // Rate limit events
        case .rateLimitsUpdated:
            // Could track rate limits
            break

        // Error events
        case .error:
            lastError = event
            onError?(event)

        // Input audio transcription
        case .inputAudioTranscriptionCompleted:
            handleInputTranscription(event)

        case .inputAudioTranscriptionFailed:
            lastError = event

        // Server bridge events (custom events from our server)
        case .transcriptUser:
            handleServerUserTranscript(event)

        case .transcriptAssistant:
            handleServerAssistantTranscript(event)

        case .transcriptAssistantDelta:
            handleServerAssistantDelta(event)

        case .serverSpeechStarted:
            isUserSpeaking = true

        case .serverSpeechStopped:
            isUserSpeaking = false

        case .responseStarted:
            currentAIResponse = ""
            isAISpeaking = true

        case .responseAudioDoneServer:
            isAISpeaking = false

        case .responseInterrupted:
            currentAIResponse = ""
            isAISpeaking = false

        case .rateLimits, .openaiDisconnected:
            // Log but no special handling
            break

        default:
            // Other events - no special handling
            break
        }
    }

    /// Clear all events
    func clearEvents() {
        events.removeAll()
        currentTranscript = ""
        userTranscript = ""
        aiTranscript = ""
        currentAIResponse = ""
        currentUserSpeech = ""
        isAISpeaking = false
        isUserSpeaking = false
        lastError = nil
        functionCalls.removeAll()
    }

    /// Start processing for a new call
    func startCall(callId: String) {
        currentCallId = callId
        clearEvents()
    }

    /// End current call processing
    func endCall() {
        currentCallId = nil
        isAISpeaking = false
        isUserSpeaking = false
    }

    /// Export events as JSON
    func exportEvents() -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let exportData = EventExport(
            callId: currentCallId ?? "",
            exportedAt: Date(),
            eventCount: events.count,
            events: events,
            transcript: TranscriptExport(
                user: userTranscript,
                ai: aiTranscript,
                combined: currentTranscript
            )
        )

        return (try? encoder.encode(exportData)) ?? Data()
    }

    /// Get events filtered by type
    func events(ofType type: EventType) -> [CallEvent] {
        events.filter { $0.eventType == type }
    }

    /// Get events in category
    func events(inCategory category: EventCategory) -> [CallEvent] {
        events.filter { $0.eventType.category == category }
    }

    // MARK: - Private Handlers

    private func handleSessionEvent(_ event: CallEvent) {
        // Could parse session configuration from payload
    }

    private func handleTranscriptionCompleted(_ event: CallEvent) {
        guard let payload = event.payload,
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let transcript = json["transcript"] as? String else { return }

        currentUserSpeech = transcript
        appendToUserTranscript(transcript)
    }

    private func handleInputTranscription(_ event: CallEvent) {
        guard let payload = event.payload,
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let transcript = json["transcript"] as? String else { return }

        appendToUserTranscript(transcript)
    }

    private func handleTextDelta(_ event: CallEvent) {
        guard let payload = event.payload,
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let delta = json["delta"] as? String else { return }

        currentAIResponse += delta
    }

    private func handleTextDone(_ event: CallEvent) {
        guard let payload = event.payload,
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            // Use accumulated delta if no final text
            if !currentAIResponse.isEmpty {
                appendToAITranscript(currentAIResponse)
            }
            return
        }

        appendToAITranscript(text)
    }

    private func handleResponseDone(_ event: CallEvent) {
        currentAIResponse = ""
        isAISpeaking = false
    }

    private func handleFunctionCallDelta(_ event: CallEvent) {
        // Accumulate function call arguments
    }

    private func handleFunctionCallDone(_ event: CallEvent) {
        guard let payload = event.payload,
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let functionCall = FunctionCallEvent(
            id: UUID(),
            timestamp: event.timestamp,
            name: json["name"] as? String ?? "unknown",
            arguments: json["arguments"] as? String ?? "{}",
            callId: json["call_id"] as? String
        )

        functionCalls.append(functionCall)
        onFunctionCall?(functionCall)
    }

    private func handleConversationItemCreated(_ event: CallEvent) {
        // New conversation item added
    }

    private func handleConversationItemDeleted(_ event: CallEvent) {
        // Conversation item removed
    }

    // MARK: - Server Bridge Event Handlers

    private func handleServerUserTranscript(_ event: CallEvent) {
        print("[EventProcessor] handleServerUserTranscript called")

        guard let payload = event.payload else {
            print("[EventProcessor] No payload in user transcript event")
            return
        }

        guard let payloadData = payload.data(using: .utf8) else {
            print("[EventProcessor] Failed to convert payload to data")
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            print("[EventProcessor] Failed to parse payload JSON")
            return
        }

        print("[EventProcessor] User transcript JSON keys: \(json.keys)")

        // Server wraps data in "data" field: { type, callSid, timestamp, data: { text, itemId } }
        let dataDict = json["data"] as? [String: Any]
        print("[EventProcessor] Data dict: \(String(describing: dataDict))")

        // Try data.text first, then fall back to top-level text for backwards compatibility
        if let transcript = dataDict?["text"] as? String ?? dataDict?["content"] as? String ?? json["text"] as? String ?? json["content"] as? String {
            print("[EventProcessor] User transcript: \(transcript)")
            currentUserSpeech = transcript
            appendToUserTranscript(transcript)
        } else {
            print("[EventProcessor] No text found in user transcript event")
        }
    }

    private func handleServerAssistantTranscript(_ event: CallEvent) {
        guard let payload = event.payload,
              let payloadData = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else { return }

        // Server wraps data in "data" field: { type, callSid, timestamp, data: { text, responseId } }
        let dataDict = json["data"] as? [String: Any]

        // Try data.text first, then fall back to top-level text for backwards compatibility
        if let transcript = dataDict?["text"] as? String ?? dataDict?["content"] as? String ?? json["text"] as? String ?? json["content"] as? String {
            appendToAITranscript(transcript)
            currentAIResponse = ""  // Clear streaming response since we have final
        }
    }

    private func handleServerAssistantDelta(_ event: CallEvent) {
        guard let payload = event.payload,
              let payloadData = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else { return }

        // Server wraps data in "data" field: { type, callSid, timestamp, data: { delta, accumulated } }
        let dataDict = json["data"] as? [String: Any]

        // Try data.delta first, then fall back to top-level delta for backwards compatibility
        if let delta = dataDict?["delta"] as? String ?? dataDict?["text"] as? String ?? json["delta"] as? String ?? json["text"] as? String {
            currentAIResponse += delta
        }
    }

    private func appendToUserTranscript(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if !userTranscript.isEmpty {
            userTranscript += " "
        }
        userTranscript += trimmed

        updateCombinedTranscript()
        onTranscriptUpdate?(userTranscript, aiTranscript)
    }

    private func appendToAITranscript(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if !aiTranscript.isEmpty {
            aiTranscript += " "
        }
        aiTranscript += trimmed

        updateCombinedTranscript()
        onTranscriptUpdate?(userTranscript, aiTranscript)
    }

    private func updateCombinedTranscript() {
        // Interleave transcripts based on event order
        // For simplicity, just combine with labels
        var combined = ""

        if !userTranscript.isEmpty {
            combined += "User: \(userTranscript)\n"
        }
        if !aiTranscript.isEmpty {
            combined += "AI: \(aiTranscript)"
        }

        currentTranscript = combined
    }
}

// MARK: - Supporting Types

/// Function call event
struct FunctionCallEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let name: String
    let arguments: String
    let callId: String?

    /// Parse arguments as JSON
    var argumentsJSON: [String: Any]? {
        guard let data = arguments.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

/// Export format for events
struct EventExport: Codable {
    let callId: String
    let exportedAt: Date
    let eventCount: Int
    let events: [CallEvent]
    let transcript: TranscriptExport
}

/// Transcript export
struct TranscriptExport: Codable {
    let user: String
    let ai: String
    let combined: String
}
