import Foundation

// MARK: - CallEvent

/// Represents a single event in a call's lifecycle
/// Used for real-time event logging and debugging
struct CallEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let callId: String
    let eventType: EventType
    let direction: EventDirection
    let payload: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        callId: String,
        eventType: EventType,
        direction: EventDirection,
        payload: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.callId = callId
        self.eventType = eventType
        self.direction = direction
        self.payload = payload
    }

    /// Create from server JSON
    init?(from json: [String: Any], callId: String) {
        guard let typeString = json["type"] as? String,
              let eventType = EventType(rawValue: typeString) else {
            return nil
        }

        self.id = UUID()
        self.timestamp = Date()
        self.callId = callId
        self.eventType = eventType
        self.direction = .incoming

        // Serialize payload back to JSON string for storage
        if let payloadData = try? JSONSerialization.data(withJSONObject: json),
           let payloadString = String(data: payloadData, encoding: .utf8) {
            self.payload = payloadString
        } else {
            self.payload = nil
        }
    }

    /// Formatted timestamp for display
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }

    /// Short description for list display
    var shortDescription: String {
        eventType.shortDescription
    }

    /// Parsed payload as dictionary
    var payloadDictionary: [String: Any]? {
        guard let payload = payload,
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}

// MARK: - EventType

/// Types of events that can occur during a call
enum EventType: String, Codable, CaseIterable {
    // Session Events
    case sessionCreated = "session.created"
    case sessionUpdated = "session.updated"

    // Audio Buffer Events
    case speechStarted = "input_audio_buffer.speech_started"
    case speechStopped = "input_audio_buffer.speech_stopped"
    case audioBufferCommitted = "input_audio_buffer.committed"
    case audioBufferCleared = "input_audio_buffer.cleared"

    // Transcription Events
    case inputTranscriptionCompleted = "conversation.item.input_audio_transcription.completed"
    case outputTranscriptDelta = "response.output_audio_transcript.delta"
    case outputTranscriptDone = "response.output_audio_transcript.done"

    // Response Events
    case responseCreated = "response.created"
    case responseAudioDelta = "response.output_audio.delta"
    case responseAudioDone = "response.output_audio.done"
    case responseTextDelta = "response.text.delta"
    case responseTextDone = "response.text.done"
    case responseDone = "response.done"
    case responseCancelled = "response.cancelled"
    case responseFunctionCallArgumentsDelta = "response.function_call_arguments.delta"
    case responseFunctionCallArgumentsDone = "response.function_call_arguments.done"

    // Conversation Events
    case conversationItemCreated = "conversation.item.created"
    case conversationItemDeleted = "conversation.item.deleted"

    // Input Audio Transcription Events
    case transcriptionCompleted = "input_audio_buffer.transcription.completed"
    case inputAudioTranscriptionCompleted = "input_audio.transcription.completed"
    case inputAudioTranscriptionFailed = "input_audio.transcription.failed"

    // Error Events
    case error = "error"
    case rateLimitsUpdated = "rate_limits.updated"

    // Custom Bridge Events
    case callConnected = "call.connected"
    case callDisconnected = "call.disconnected"
    case configUpdated = "config.updated"
    case connectionDropped = "connection.dropped"
    case recordingSaved = "recording.saved"

    // Twilio Events
    case twilioMark = "twilio.mark"

    /// Human-readable name
    var displayName: String {
        switch self {
        case .sessionCreated: return "Session Created"
        case .sessionUpdated: return "Session Updated"
        case .speechStarted: return "Speech Started"
        case .speechStopped: return "Speech Stopped"
        case .audioBufferCommitted: return "Audio Committed"
        case .audioBufferCleared: return "Audio Cleared"
        case .inputTranscriptionCompleted: return "User Transcript"
        case .outputTranscriptDelta: return "AI Transcript (partial)"
        case .outputTranscriptDone: return "AI Transcript"
        case .responseCreated: return "Response Started"
        case .responseAudioDelta: return "Audio Chunk"
        case .responseAudioDone: return "Audio Complete"
        case .responseTextDelta: return "Text Delta"
        case .responseTextDone: return "Text Done"
        case .responseDone: return "Response Complete"
        case .responseCancelled: return "Response Cancelled"
        case .responseFunctionCallArgumentsDelta: return "Function Args Delta"
        case .responseFunctionCallArgumentsDone: return "Function Args Done"
        case .conversationItemCreated: return "Item Created"
        case .conversationItemDeleted: return "Item Deleted"
        case .transcriptionCompleted: return "Transcription Done"
        case .inputAudioTranscriptionCompleted: return "Audio Transcription"
        case .inputAudioTranscriptionFailed: return "Transcription Failed"
        case .error: return "Error"
        case .rateLimitsUpdated: return "Rate Limits"
        case .callConnected: return "Call Connected"
        case .callDisconnected: return "Call Disconnected"
        case .configUpdated: return "Config Updated"
        case .connectionDropped: return "Connection Lost"
        case .recordingSaved: return "Recording Saved"
        case .twilioMark: return "Twilio Mark"
        }
    }

    /// Short description for compact display
    var shortDescription: String {
        switch self {
        case .sessionCreated: return "Session started"
        case .sessionUpdated: return "Config updated"
        case .speechStarted: return "User speaking..."
        case .speechStopped: return "User stopped"
        case .audioBufferCommitted: return "Audio sent"
        case .audioBufferCleared: return "Audio cleared"
        case .inputTranscriptionCompleted: return "Transcript ready"
        case .outputTranscriptDelta: return "AI speaking..."
        case .outputTranscriptDone: return "AI transcript"
        case .responseCreated: return "AI responding..."
        case .responseAudioDelta: return "Audio streaming"
        case .responseAudioDone: return "Audio done"
        case .responseTextDelta: return "Text streaming"
        case .responseTextDone: return "Text complete"
        case .responseDone: return "Response complete"
        case .responseCancelled: return "Interrupted"
        case .responseFunctionCallArgumentsDelta: return "Building args"
        case .responseFunctionCallArgumentsDone: return "Args complete"
        case .conversationItemCreated: return "Item added"
        case .conversationItemDeleted: return "Item removed"
        case .transcriptionCompleted: return "Transcript ready"
        case .inputAudioTranscriptionCompleted: return "Audio transcribed"
        case .inputAudioTranscriptionFailed: return "Transcription failed"
        case .error: return "Error occurred"
        case .rateLimitsUpdated: return "Rate limits"
        case .callConnected: return "Call connected"
        case .callDisconnected: return "Call ended"
        case .configUpdated: return "Settings applied"
        case .connectionDropped: return "Connection lost"
        case .recordingSaved: return "Recording saved"
        case .twilioMark: return "Playback mark"
        }
    }

    /// Icon for display
    var icon: String {
        switch self {
        case .sessionCreated, .sessionUpdated: return "gearshape"
        case .speechStarted: return "waveform"
        case .speechStopped: return "waveform.slash"
        case .audioBufferCommitted, .audioBufferCleared: return "arrow.up.circle"
        case .inputTranscriptionCompleted, .transcriptionCompleted, .inputAudioTranscriptionCompleted: return "text.bubble"
        case .inputAudioTranscriptionFailed: return "text.bubble.fill"
        case .outputTranscriptDelta, .outputTranscriptDone: return "text.bubble.fill"
        case .responseCreated: return "brain"
        case .responseAudioDelta, .responseAudioDone: return "speaker.wave.2"
        case .responseTextDelta, .responseTextDone: return "text.alignleft"
        case .responseDone: return "checkmark.circle"
        case .responseCancelled: return "xmark.circle"
        case .responseFunctionCallArgumentsDelta, .responseFunctionCallArgumentsDone: return "function"
        case .conversationItemCreated: return "plus.circle"
        case .conversationItemDeleted: return "minus.circle"
        case .error: return "exclamationmark.triangle"
        case .rateLimitsUpdated: return "gauge"
        case .callConnected: return "phone.fill"
        case .callDisconnected: return "phone.down"
        case .configUpdated: return "slider.horizontal.3"
        case .connectionDropped: return "wifi.exclamationmark"
        case .recordingSaved: return "waveform.circle"
        case .twilioMark: return "bookmark"
        }
    }

    /// Category for filtering
    var category: EventCategory {
        switch self {
        case .sessionCreated, .sessionUpdated, .configUpdated:
            return .session
        case .speechStarted, .speechStopped, .audioBufferCommitted, .audioBufferCleared:
            return .audio
        case .inputTranscriptionCompleted, .outputTranscriptDelta, .outputTranscriptDone,
             .transcriptionCompleted, .inputAudioTranscriptionCompleted, .inputAudioTranscriptionFailed:
            return .transcript
        case .responseCreated, .responseAudioDelta, .responseAudioDone, .responseDone, .responseCancelled,
             .responseTextDelta, .responseTextDone, .responseFunctionCallArgumentsDelta, .responseFunctionCallArgumentsDone:
            return .response
        case .conversationItemCreated, .conversationItemDeleted:
            return .session
        case .error, .rateLimitsUpdated, .connectionDropped:
            return .error
        case .callConnected, .callDisconnected, .recordingSaved, .twilioMark:
            return .call
        }
    }

    /// Whether this event type generates high volume (for filtering)
    var isHighVolume: Bool {
        switch self {
        case .responseAudioDelta, .outputTranscriptDelta:
            return true
        default:
            return false
        }
    }
}

// MARK: - EventCategory

/// Categories for grouping and filtering events
enum EventCategory: String, CaseIterable, Identifiable {
    case session
    case audio
    case transcript
    case response
    case error
    case call
    case other

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .session: return "gearshape.2"
        case .audio: return "waveform"
        case .transcript: return "text.bubble"
        case .response: return "brain"
        case .error: return "exclamationmark.triangle"
        case .call: return "phone"
        case .other: return "questionmark.circle"
        }
    }
}

// MARK: - EventDirection

/// Direction of event flow
enum EventDirection: String, Codable {
    case incoming  // Server → Client
    case outgoing  // Client → Server

    var displayName: String {
        switch self {
        case .incoming: return "← IN"
        case .outgoing: return "→ OUT"
        }
    }

    var icon: String {
        switch self {
        case .incoming: return "arrow.down.left"
        case .outgoing: return "arrow.up.right"
        }
    }
}
