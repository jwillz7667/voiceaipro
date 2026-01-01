# VoiceAI Pro: Sequential Implementation Prompts

## For Advanced LLM Coding Assistants

---

## Preamble: Instructions for the Coding Assistant

Before we begin, internalize these directives:

1. **NEVER use placeholders, mock code, TODO comments, or stub implementations.** Every line you write must be production-ready, fully functional code.

2. **Visualize the complete application** in your mind's eye before writing any code. See the data flowing from microphone → Twilio SDK → WebSocket → Bridge Server → OpenAI Realtime API → back through the same path to the speaker. Understand every transformation, every event, every state change.

3. **Reference the Technical Specification** provided alongside these prompts. It contains the exact API schemas, event types, configuration structures, and architectural decisions you must follow.

4. **The OpenAI Realtime API is GA (General Availability).** Use model `gpt-realtime`, WebSocket URL `wss://api.openai.com/v1/realtime?model=gpt-realtime`. Do NOT use beta headers.

5. **Twilio Voice iOS SDK version is 6.13.x.** Install via Swift Package Manager from `https://github.com/twilio/twilio-voice-ios`.

6. **Audio format conversion is critical:**
   - Twilio: μ-law 8kHz mono
   - OpenAI: PCM16 24kHz mono
   - You must implement bidirectional conversion with proper resampling.

7. **Every feature must work.** Call recording, event logging, VAD configuration, voice selection—all must be fully implemented with real persistence.

---

## Prompt Sequence Overview

| # | Phase | Focus Area |
|---|-------|------------|
| 1 | Foundation | WebSocket Bridge Server - Core Structure |
| 2 | Server | Twilio Media Stream Handler |
| 3 | Server | OpenAI Realtime API Integration |
| 4 | Server | Audio Bridge & Format Conversion |
| 5 | Server | REST API & Database Layer |
| 6 | Server | Call Recording System |
| 7 | iOS | Project Setup & Architecture |
| 8 | iOS | Twilio Voice SDK Integration |
| 9 | iOS | WebSocket Client & Event System |
| 10 | iOS | SwiftData Models & Persistence |
| 11 | iOS | Dashboard & Dialer Views |
| 12 | iOS | Active Call & Controls Views |
| 13 | iOS | Settings & Configuration Views |
| 14 | iOS | Event Log & History Views |
| 15 | iOS | Recordings & Prompts Management |
| 16 | Integration | End-to-End Testing & Polish |

---

## PROMPT 1: WebSocket Bridge Server - Core Structure

```
You are building a production Node.js WebSocket bridge server that connects Twilio's Media Streams to OpenAI's Realtime API for bidirectional voice AI calls.

CONTEXT:
- This server runs on Railway (supports WebSockets natively)
- It handles multiple concurrent calls, each with its own session
- It bridges audio between Twilio (μ-law 8kHz) and OpenAI (PCM16 24kHz)
- It provides REST endpoints for the iOS app and WebSocket for real-time events

REQUIREMENTS:
1. Create the complete project structure:
   /server
   ├── package.json (with exact dependencies and versions)
   ├── src/
   │   ├── index.js (main entry, Express + WebSocket server setup)
   │   ├── config/
   │   │   └── environment.js (environment variable validation)
   │   ├── websocket/
   │   │   ├── twilioMediaHandler.js
   │   │   ├── openaiRealtimeHandler.js
   │   │   ├── iosClientHandler.js
   │   │   └── connectionManager.js
   │   ├── audio/
   │   │   └── converter.js
   │   ├── routes/
   │   │   ├── token.js
   │   │   ├── calls.js
   │   │   ├── recordings.js
   │   │   ├── prompts.js
   │   │   └── twiml.js
   │   ├── services/
   │   │   ├── twilioService.js
   │   │   ├── openaiService.js
   │   │   ├── recordingService.js
   │   │   └── eventLogger.js
   │   ├── db/
   │   │   ├── pool.js
   │   │   ├── migrations/
   │   │   └── queries/
   │   └── utils/
   │       └── logger.js

2. Implement src/index.js with:
   - Express server on configurable port
   - HTTP server that upgrades to WebSocket
   - Three WebSocket endpoints:
     * /media-stream (for Twilio Media Streams)
     * /ios-client (for iOS app control channel)
     * /events/:callId (for iOS app event streaming)
   - Graceful shutdown handling
   - Request logging middleware

3. Implement src/config/environment.js that:
   - Validates all required environment variables exist
   - Provides typed access to configuration
   - Throws clear errors on missing config

4. Implement src/websocket/connectionManager.js that:
   - Tracks all active call sessions by callSid
   - Stores references to: Twilio WS, OpenAI WS, iOS WS, session config
   - Provides methods: createSession, getSession, destroySession, broadcastEvent
   - Handles cleanup on any connection drop

CONSTRAINTS:
- Use ES modules (type: "module" in package.json)
- Use ws library version 8.x for WebSocket handling
- Use express 4.x
- Use pg for PostgreSQL (connection pooling)
- Include comprehensive error handling
- Log all significant events with timestamps

OUTPUT:
Provide the complete implementation of all files mentioned above. Every function must be fully implemented with real logic. Do not use any placeholders or TODO comments.
```

---

## PROMPT 2: Twilio Media Stream Handler

```
Continue building the VoiceAI Pro WebSocket bridge server. Now implement the Twilio Media Stream handler.

CONTEXT:
You have the core server structure from Prompt 1. Now implement the handler that:
- Receives incoming WebSocket connections from Twilio when a call starts
- Processes the Twilio Media Stream protocol
- Extracts μ-law audio and forwards it (after conversion) to OpenAI
- Receives audio from OpenAI and sends it back to Twilio
- Handles call lifecycle events (start, media, stop, mark)

TWILIO MEDIA STREAM PROTOCOL:
Twilio sends these event types:
1. "connected" - WebSocket connected, contains protocol version
2. "start" - Stream started, contains streamSid, callSid, customParameters
3. "media" - Audio data, contains: media.track, media.chunk (base64 μ-law), media.timestamp
4. "stop" - Stream ended
5. "mark" - Audio playback marker (for synchronization)

To send audio back to Twilio:
{
  "event": "media",
  "streamSid": "<streamSid>",
  "media": {
    "payload": "<base64 μ-law audio>"
  }
}

To clear the audio queue (for interruption):
{
  "event": "clear",
  "streamSid": "<streamSid>"
}

REQUIREMENTS:
Implement src/websocket/twilioMediaHandler.js with:

1. handleTwilioConnection(ws, req) function that:
   - Sets up message handlers for the WebSocket
   - Parses incoming JSON messages
   - Routes to appropriate handlers based on event type

2. handleConnected(session, data) - logs connection, stores protocol version

3. handleStart(session, data) that:
   - Extracts callSid, streamSid, customParameters
   - Creates a new call session in connectionManager
   - Initializes OpenAI Realtime connection (call openaiRealtimeHandler)
   - Stores session configuration from customParameters
   - Logs the call start event to database

4. handleMedia(session, data) that:
   - Extracts base64 μ-law audio from media.chunk
   - Converts to PCM16 24kHz (use audio converter)
   - Buffers appropriately (OpenAI expects ~100ms chunks)
   - Sends to OpenAI via input_audio_buffer.append event
   - Tracks audio timestamps for synchronization

5. handleStop(session, data) that:
   - Logs call end
   - Calculates call duration
   - Updates database with final status
   - Triggers recording finalization if enabled
   - Cleans up OpenAI connection
   - Removes session from connectionManager

6. handleMark(session, data) - logs playback markers for debugging

7. sendAudioToTwilio(session, pcm24kAudio) that:
   - Converts PCM16 24kHz to μ-law 8kHz
   - Encodes to base64
   - Sends via the Twilio WebSocket with correct streamSid

8. clearTwilioAudio(session) - sends clear event for interruption

IMPORTANT:
- Audio buffering is critical. Twilio sends small ~20ms chunks, OpenAI expects ~100-200ms
- Implement a proper buffer that accumulates audio before sending
- Handle the case where the Twilio WebSocket closes unexpectedly
- All audio must be processed in the correct endianness (little-endian for PCM16)

OUTPUT:
Complete implementation of twilioMediaHandler.js with all functions fully working. Include detailed comments explaining the audio flow.
```

---

## PROMPT 3: OpenAI Realtime API Integration

```
Continue building the VoiceAI Pro WebSocket bridge server. Now implement the OpenAI Realtime API handler.

CONTEXT:
You have the Twilio handler from Prompt 2. Now implement the handler that:
- Connects to OpenAI's Realtime API via WebSocket
- Manages the session configuration
- Handles all Realtime API events
- Forwards audio back to Twilio
- Logs all events for the iOS app

OPENAI REALTIME API DETAILS:
Connection: wss://api.openai.com/v1/realtime?model=gpt-realtime
Auth header: Authorization: Bearer <OPENAI_API_KEY>

Session configuration (send as session.update after connection):
{
  "type": "session.update",
  "session": {
    "type": "realtime",
    "model": "gpt-realtime",
    "instructions": "<system prompt>",
    "audio": {
      "input": {
        "format": { "type": "audio/pcm", "rate": 24000 },
        "transcription": { "model": "whisper-1" },
        "noise_reduction": { "type": "near_field" }, // optional
        "turn_detection": {
          "type": "server_vad",
          "threshold": 0.5,
          "prefix_padding_ms": 300,
          "silence_duration_ms": 500,
          "create_response": true,
          "interrupt_response": true
        }
      },
      "output": {
        "format": { "type": "audio/pcm", "rate": 24000 },
        "voice": "marin",
        "speed": 1.0
      }
    },
    "tools": [],
    "tool_choice": "auto",
    "temperature": 0.8,
    "max_output_tokens": 4096
  }
}

Key server events to handle:
- session.created: Session ready
- session.updated: Config confirmed
- input_audio_buffer.speech_started: User started speaking
- input_audio_buffer.speech_stopped: User stopped speaking
- conversation.item.input_audio_transcription.completed: User transcript
- response.created: AI starting response
- response.output_audio.delta: Audio chunk (base64 PCM16 24kHz)
- response.output_audio.done: Audio complete
- response.output_audio_transcript.delta: AI transcript chunk
- response.output_audio_transcript.done: AI transcript complete
- response.done: Response complete
- error: Error occurred

REQUIREMENTS:
Implement src/websocket/openaiRealtimeHandler.js with:

1. connectToOpenAI(session, config) that:
   - Creates WebSocket connection to OpenAI
   - Sets Authorization header
   - Waits for session.created event
   - Sends session.update with full configuration
   - Returns promise that resolves when session.updated received
   - Stores the OpenAI WebSocket in the session

2. handleOpenAIMessage(session, message) that:
   - Parses the JSON message
   - Routes to appropriate handler based on type
   - Logs ALL events to the event logger service
   - Broadcasts events to iOS client WebSocket

3. Event handlers for each event type:
   - handleSessionCreated(session, data)
   - handleSessionUpdated(session, data)
   - handleSpeechStarted(session, data) - may need to interrupt playback
   - handleSpeechStopped(session, data)
   - handleInputTranscription(session, data) - save to transcripts table
   - handleResponseCreated(session, data)
   - handleAudioDelta(session, data) - forward to Twilio
   - handleAudioDone(session, data)
   - handleTranscriptDelta(session, data) - accumulate transcript
   - handleTranscriptDone(session, data) - save to transcripts table
   - handleResponseDone(session, data)
   - handleError(session, data) - log and potentially reconnect

4. sendAudioToOpenAI(session, pcm24kBase64) that:
   - Sends input_audio_buffer.append event
   - Handles buffering appropriately

5. commitAudioBuffer(session) - sends input_audio_buffer.commit

6. cancelResponse(session) - sends response.cancel for interruption

7. updateSessionConfig(session, newConfig) that:
   - Merges new config with existing
   - Sends session.update event
   - Called when iOS app changes settings mid-call

8. closeOpenAIConnection(session) - graceful cleanup

IMPORTANT AUDIO HANDLING:
- response.output_audio.delta contains base64-encoded PCM16 24kHz audio
- Decode it, then pass to Twilio handler for conversion and sending
- Handle interruption: when speech_started fires during AI audio playback:
  1. Call cancelResponse() to stop OpenAI
  2. Call clearTwilioAudio() to stop Twilio playback
  3. Clear any pending audio buffers

OUTPUT:
Complete implementation of openaiRealtimeHandler.js with all functions. Include robust error handling and reconnection logic.
```

---

## PROMPT 4: Audio Bridge & Format Conversion

```
Continue building the VoiceAI Pro WebSocket bridge server. Now implement the audio conversion system.

CONTEXT:
You need to convert audio bidirectionally between:
- Twilio: μ-law (G.711) encoded, 8kHz sample rate, mono
- OpenAI: Linear PCM16 (signed 16-bit little-endian), 24kHz sample rate, mono

This is CRITICAL for the system to work. Incorrect conversion = garbled audio.

AUDIO ENGINEERING DETAILS:

μ-law (G.711):
- 8-bit samples, logarithmically compressed
- Dynamic range: ~13 bits effective
- Bias: 33 (0x21)
- Clip value: 32635

PCM16:
- 16-bit signed samples
- Little-endian byte order
- Range: -32768 to 32767

Resampling:
- 8kHz → 24kHz: 3x interpolation (upsample)
- 24kHz → 8kHz: 3x decimation (downsample)
- Use linear interpolation for simplicity (or implement a proper low-pass filter if quality is poor)

REQUIREMENTS:
Implement src/audio/converter.js with:

1. MULAW_DECODE_TABLE - precomputed lookup table for μ-law to linear PCM16
   (256 entries, one for each possible μ-law byte value)

2. MULAW_ENCODE_TABLE - precomputed lookup table or function for PCM16 to μ-law

3. decodeMulaw(mulawBuffer) → Int16Array
   - Input: Buffer of μ-law bytes
   - Output: Int16Array of PCM16 samples at 8kHz
   - Use lookup table for each byte

4. encodeMulaw(pcm16Array) → Buffer
   - Input: Int16Array of PCM16 samples
   - Output: Buffer of μ-law bytes
   - Implement the μ-law encoding algorithm or use lookup

5. resample8kTo24k(pcm8k) → Int16Array
   - Input: Int16Array at 8kHz
   - Output: Int16Array at 24kHz (3x the length)
   - Implement linear interpolation between samples
   - Handle edge cases properly

6. resample24kTo8k(pcm24k) → Int16Array
   - Input: Int16Array at 24kHz
   - Output: Int16Array at 8kHz (1/3 the length)
   - Take every 3rd sample (simple decimation)
   - Optional: implement averaging for better quality

7. mulawToOpenAI(mulawBase64) → string (base64 PCM16 24kHz)
   - Full pipeline: decode base64 → decode μ-law → resample → encode base64
   - This is called for Twilio → OpenAI direction

8. openaiToMulaw(pcm24kBase64) → string (base64 μ-law 8kHz)
   - Full pipeline: decode base64 → resample → encode μ-law → encode base64
   - This is called for OpenAI → Twilio direction

9. AudioBuffer class for accumulating audio chunks:
   - constructor(targetDurationMs, sampleRate)
   - append(samples: Int16Array) → void
   - isReady() → boolean (true when enough samples accumulated)
   - flush() → Int16Array (returns accumulated samples and clears buffer)
   - clear() → void

TESTING HELPERS:
10. generateTestTone(frequency, durationMs, sampleRate) → Int16Array
    - Generate a sine wave for testing the pipeline

11. calculateRMS(samples) → number
    - Calculate RMS level for audio level monitoring

μ-LAW ENCODING ALGORITHM (for reference):
```
function encodeMulawSample(sample) {
  const MULAW_MAX = 0x1FFF;
  const MULAW_BIAS = 33;
  
  let sign = (sample >> 8) & 0x80;
  if (sign !== 0) sample = -sample;
  sample = sample + MULAW_BIAS;
  if (sample > MULAW_MAX) sample = MULAW_MAX;
  
  let exponent = 7;
  for (let expMask = 0x4000; (sample & expMask) === 0 && exponent > 0; exponent--, expMask >>= 1);
  
  let mantissa = (sample >> (exponent + 3)) & 0x0F;
  let mulawByte = ~(sign | (exponent << 4) | mantissa);
  
  return mulawByte & 0xFF;
}
```

OUTPUT:
Complete implementation of converter.js with all functions and lookup tables. Include unit tests at the bottom of the file that verify the conversion pipeline works correctly (decode → resample → encode should produce valid audio).
```

---

## PROMPT 5: REST API & Database Layer

```
Continue building the VoiceAI Pro WebSocket bridge server. Now implement the REST API endpoints and database layer.

CONTEXT:
The iOS app needs REST endpoints for:
- Getting Twilio access tokens
- Managing calls
- Accessing call history
- Managing recordings
- Managing saved prompts
- Serving TwiML for Twilio webhooks

DATABASE:
PostgreSQL on Railway. Use connection pooling. Reference the schema from the Technical Specification.

REQUIREMENTS:

1. Implement src/db/pool.js:
   - Create pg Pool with DATABASE_URL from environment
   - Configure connection pool (min: 2, max: 10)
   - Handle connection errors gracefully
   - Export query helper function

2. Implement src/db/migrations/001_initial.sql:
   - Complete SQL to create all tables from the spec
   - Include indexes
   - Use IF NOT EXISTS for idempotency

3. Implement src/db/queries/calls.js:
   - createCallSession(data) → returns created session
   - updateCallSession(callSid, updates)
   - getCallSession(callSid)
   - getCallHistory(userId, limit, offset)
   - getCallEvents(callSessionId)

4. Implement src/db/queries/recordings.js:
   - createRecording(data)
   - getRecording(id)
   - getRecordingsByCall(callSessionId)
   - getRecordingsByUser(userId, limit, offset)
   - deleteRecording(id)

5. Implement src/db/queries/prompts.js:
   - createPrompt(data)
   - updatePrompt(id, updates)
   - deletePrompt(id)
   - getPrompt(id)
   - getPromptsByUser(userId)
   - setDefaultPrompt(userId, promptId)

6. Implement src/db/queries/transcripts.js:
   - addTranscript(data)
   - getTranscriptsByCall(callSessionId)

7. Implement src/routes/token.js:
   POST /api/token
   - Body: { identity: string }
   - Generate Twilio access token with Voice grant
   - Include outgoing application SID
   - Allow incoming calls
   - Return: { token: string, identity: string }

8. Implement src/routes/calls.js:
   POST /api/calls/outgoing
   - Body: { to: string, promptId?: string, config?: object }
   - Initiate outgoing call via Twilio REST API
   - Return: { callSid: string, status: string }
   
   POST /api/calls/:callSid/end
   - End the specified call
   
   GET /api/calls/history
   - Query: { limit?, offset?, userId }
   - Return paginated call history with basic info
   
   GET /api/calls/:callSid
   - Return full call details including events and transcripts

9. Implement src/routes/recordings.js:
   GET /api/recordings
   - Query: { userId, limit?, offset? }
   - Return paginated recordings list
   
   GET /api/recordings/:id
   - Return recording metadata
   
   GET /api/recordings/:id/audio
   - Stream the actual audio file
   - Set correct Content-Type header
   
   DELETE /api/recordings/:id
   - Delete recording file and database entry

10. Implement src/routes/prompts.js:
    POST /api/prompts
    - Body: { name, instructions, voice?, vadConfig?, userId }
    - Create new saved prompt
    
    GET /api/prompts
    - Query: { userId }
    - Return all prompts for user
    
    PUT /api/prompts/:id
    - Update prompt
    
    DELETE /api/prompts/:id
    - Delete prompt
    
    POST /api/prompts/:id/default
    - Set as default prompt for user

11. Implement src/routes/twiml.js:
    POST /api/twiml/outgoing
    - Called by Twilio when outgoing call connects
    - Return TwiML with <Connect><Stream> to /media-stream
    - Include custom parameters from request
    
    POST /api/twiml/incoming
    - Called by Twilio for incoming calls
    - Return TwiML with greeting and <Connect><Stream>
    
    POST /api/twiml/status
    - Status callback webhook
    - Update call status in database

12. Wire all routes in src/index.js with proper middleware:
    - JSON body parser
    - CORS (configure for iOS app)
    - Request logging
    - Error handling middleware

OUTPUT:
Complete implementation of all database queries and REST routes. Include input validation using a validation library or manual checks. All endpoints must be fully functional.
```

---

## PROMPT 6: Call Recording System

```
Continue building the VoiceAI Pro WebSocket bridge server. Now implement the call recording system.

CONTEXT:
The system should record calls by capturing and mixing both sides of the audio (user and AI). Recordings are stored on disk (Railway volume) or S3-compatible storage.

REQUIREMENTS:

1. Implement src/services/recordingService.js:

   class RecordingService {
     constructor(storagePath) - initialize with base storage path
     
     startRecording(callSid, config) {
       - Create a new recording session
       - Open file handle for writing WAV
       - Write WAV header (placeholder for size, will update at end)
       - Store reference in active recordings map
       - Return recordingId
     }
     
     appendUserAudio(callSid, pcm16Samples) {
       - Buffer user audio (from Twilio, after conversion)
       - Track timestamp for synchronization
     }
     
     appendAIAudio(callSid, pcm16Samples) {
       - Buffer AI audio (from OpenAI, before conversion)
       - Track timestamp for synchronization
     }
     
     async mixAndWrite(callSid) {
       - Called periodically or on buffer threshold
       - Mix user and AI audio buffers (simple addition with clipping)
       - Write mixed PCM16 to WAV file
       - Clear processed buffers
     }
     
     async stopRecording(callSid) {
       - Flush remaining buffers
       - Calculate final file size
       - Update WAV header with correct sizes
       - Close file handle
       - Calculate duration
       - Create database record
       - Return recording metadata
     }
     
     async getRecordingPath(recordingId) {
       - Return full path to recording file
     }
     
     async deleteRecording(recordingId) {
       - Delete file from storage
       - Remove database record
     }
   }

2. WAV file format implementation:
   - 16-bit PCM
   - 24kHz sample rate (or 8kHz if we want smaller files)
   - Mono (mixed)
   - Proper RIFF/WAVE headers

3. Audio mixing logic:
   - Both streams are PCM16 at 24kHz
   - Simple mixing: output = (user + ai) / 2 (with clamping to prevent overflow)
   - Handle timing differences (one side might have gaps)

4. Update twilioMediaHandler.js:
   - After converting Twilio audio to PCM16 24kHz, also send to recordingService.appendUserAudio()

5. Update openaiRealtimeHandler.js:
   - When receiving audio delta, also send to recordingService.appendAIAudio()
   - On call end, call recordingService.stopRecording()

6. Create src/services/eventLogger.js:
   
   class EventLogger {
     constructor(db)
     
     async logEvent(callSessionId, eventType, direction, payload) {
       - Insert into call_events table
       - Also emit to any connected iOS WebSocket for real-time viewing
     }
     
     async getEvents(callSessionId, filters?) {
       - Retrieve events with optional filtering by type
     }
     
     async getRecentEvents(callSessionId, limit) {
       - Get last N events for a call
     }
   }

7. Wire event logging throughout the system:
   - Log when Twilio stream starts/stops
   - Log when OpenAI session created/updated
   - Log VAD events (speech started/stopped)
   - Log transcription completions
   - Log response events
   - Log errors

8. Implement iOS event streaming via WebSocket:
   
   In src/websocket/iosClientHandler.js:
   
   handleIOSConnection(ws, req) {
     - Parse callSid from URL or initial message
     - Register this WebSocket with the call session
     - Send buffered recent events immediately
     - Keep connection open for real-time event streaming
   }
   
   broadcastToIOS(callSid, event) {
     - Find iOS WebSocket for this call
     - Send event as JSON
   }

OUTPUT:
Complete implementation of the recording service, event logger, and iOS event streaming. The recording system must produce valid WAV files that can be played back. All events must be properly logged and streamed.
```

---

## PROMPT 7: iOS Project Setup & Architecture

```
Now we begin the iOS application. Create the complete Xcode project structure and foundational architecture.

CONTEXT:
- iOS 17+ minimum deployment target
- SwiftUI as primary UI framework
- MVVM architecture with Coordinators for navigation
- SwiftData for local persistence
- Combine for reactive programming

PROJECT SETUP:
Name: VoiceAIPro
Bundle ID: com.yourcompany.voiceaipro
Team: (user will fill in)

REQUIREMENTS:

1. Create the complete project structure as outlined in the Technical Specification (Section 6.1)

2. Implement VoiceAIPro/App/VoiceAIProApp.swift:
   - Main app entry point
   - Configure SwiftData ModelContainer
   - Set up environment objects for dependency injection
   - Configure appearance customization

3. Implement VoiceAIPro/App/AppDelegate.swift:
   - UIApplicationDelegate for push notification handling
   - Register for VoIP push notifications
   - Handle PushKit delegate methods
   - Initialize Twilio Voice SDK

4. Create VoiceAIPro/Core/Models/ with all data models:

   CallSession.swift:
   ```swift
   struct CallSession: Identifiable {
       let id: UUID
       var callSid: String?
       var direction: CallDirection
       var phoneNumber: String
       var status: CallStatus
       var startedAt: Date
       var endedAt: Date?
       var durationSeconds: Int?
       var promptId: UUID?
       var config: RealtimeConfig
   }
   
   enum CallDirection: String, Codable {
       case inbound, outbound
   }
   
   enum CallStatus: String, Codable {
       case initiating, ringing, connected, ended, failed
   }
   ```

   RealtimeConfig.swift:
   - Full implementation as specified in Technical Spec Section 6.3
   - All enums, structs for VAD, voices, etc.
   - Codable conformance for persistence and API transmission

   CallEvent.swift:
   - As specified in Technical Spec Section 6.4
   - All event types enumerated
   - Direction enum

   Prompt.swift:
   ```swift
   struct Prompt: Identifiable, Codable {
       let id: UUID
       var name: String
       var instructions: String
       var voice: RealtimeVoice
       var vadConfig: VADConfig
       var isDefault: Bool
       var createdAt: Date
       var updatedAt: Date
   }
   ```

5. Create VoiceAIPro/Utilities/Constants.swift:
   ```swift
   enum Constants {
       enum API {
           static let baseURL = "https://your-server.railway.app"
           static let wsURL = "wss://your-server.railway.app"
       }
       
       enum Twilio {
           // Will be configured at runtime
       }
       
       enum Audio {
           static let sampleRate = 24000
           static let channelCount = 1
           static let bitsPerSample = 16
       }
   }
   ```

6. Create VoiceAIPro/Utilities/Extensions/:
   - Color+VoiceAI.swift (color palette from spec)
   - View+Extensions.swift (common modifiers)
   - Date+Extensions.swift (formatting)
   - String+Extensions.swift (phone number formatting)

7. Create VoiceAIPro/Core/Managers/AppState.swift:
   ```swift
   @MainActor
   class AppState: ObservableObject {
       @Published var currentCall: CallSession?
       @Published var isCallActive: Bool = false
       @Published var callStatus: CallStatus = .ended
       @Published var realtimeConfig: RealtimeConfig = .default
       @Published var events: [CallEvent] = []
       @Published var connectionState: ConnectionState = .disconnected
       
       enum ConnectionState {
           case disconnected, connecting, connected, error(String)
       }
   }
   ```

8. Create dependency injection container:
   VoiceAIPro/Core/DI/DIContainer.swift
   - Holds references to all services
   - Provides factory methods
   - Supports testing with mock implementations

OUTPUT:
Complete implementation of all foundational files. The project should compile (though not fully functional yet). Use proper Swift conventions, documentation comments, and organize imports correctly.
```

---

## PROMPT 8: Twilio Voice SDK Integration

```
Continue building the iOS app. Now implement the Twilio Voice SDK integration.

CONTEXT:
The Twilio Voice iOS SDK handles:
- VoIP calling (WebRTC-based)
- Push notifications for incoming calls
- CallKit integration for native call UI
- Audio session management

SDK: TwilioVoice 6.13.x via Swift Package Manager

REQUIREMENTS:

1. Implement VoiceAIPro/Core/Services/TwilioVoiceService.swift:

   ```swift
   @MainActor
   class TwilioVoiceService: NSObject, ObservableObject {
       @Published var isRegistered: Bool = false
       @Published var activeCall: TVOCall?
       @Published var callInvite: TVOCallInvite?
       
       private var accessToken: String?
       private var deviceToken: Data?
       
       // Initialize and register
       func initialize() async throws
       func registerForPushNotifications()
       func unregister()
       
       // Call management
       func makeCall(to: String, params: [String: String]) async throws -> TVOCall
       func acceptIncomingCall() throws -> TVOCall
       func rejectIncomingCall()
       func endCall()
       func toggleMute(_ muted: Bool)
       func toggleSpeaker(_ speaker: Bool)
       func sendDigits(_ digits: String)
       
       // Token management
       func fetchAccessToken() async throws -> String
       func refreshTokenIfNeeded() async
   }
   ```

2. Implement TVOCallDelegate:
   - call(_:didFailToConnectWithError:)
   - callDidStartRinging(_:)
   - callDidConnect(_:)
   - call(_:didDisconnectWithError:)
   - call(_:isReconnectingWithError:)
   - callDidReconnect(_:)
   - call(_:didReceiveQualityWarnings:, previousWarnings:)

3. Implement TVONotificationDelegate:
   - callInviteReceived(_:)
   - cancelledCallInviteReceived(_:, error:)

4. Implement VoiceAIPro/Core/Services/CallKitManager.swift:

   ```swift
   class CallKitManager: NSObject {
       private let callController: CXCallController
       private let provider: CXProvider
       
       // Provider configuration
       static var providerConfiguration: CXProviderConfiguration {
           let config = CXProviderConfiguration()
           config.localizedName = "VoiceAI Pro"
           config.supportsVideo = false
           config.maximumCallsPerCallGroup = 1
           config.supportedHandleTypes = [.phoneNumber, .generic]
           // Configure icon, ringtone, etc.
           return config
       }
       
       // Report call events to CallKit
       func reportIncomingCall(uuid: UUID, handle: String) async throws
       func reportOutgoingCall(uuid: UUID, handle: String)
       func reportCallConnected(uuid: UUID)
       func reportCallEnded(uuid: UUID, reason: CXCallEndedReason)
       
       // Request actions
       func startCall(uuid: UUID, handle: String) async throws
       func endCall(uuid: UUID) async throws
       func setMuted(uuid: UUID, muted: Bool) async throws
       func setHeld(uuid: UUID, onHold: Bool) async throws
   }
   ```

5. Implement CXProviderDelegate:
   - providerDidReset(_:)
   - provider(_:perform startCallAction:)
   - provider(_:perform answerCallAction:)
   - provider(_:perform endCallAction:)
   - provider(_:perform setMutedCallAction:)
   - provider(_:perform setHeldCallAction:)
   - provider(_:didActivate audioSession:)
   - provider(_:didDeactivate audioSession:)

6. Implement VoiceAIPro/Core/Services/AudioSessionManager.swift:

   ```swift
   class AudioSessionManager {
       static let shared = AudioSessionManager()
       
       func configureForVoIP() throws {
           let session = AVAudioSession.sharedInstance()
           try session.setCategory(.playAndRecord, 
                                   mode: .voiceChat,
                                   options: [.allowBluetooth, .defaultToSpeaker])
           try session.setActive(true)
       }
       
       func activateSession() throws
       func deactivateSession() throws
       func setSpeakerEnabled(_ enabled: Bool) throws
       
       // Audio route monitoring
       func getCurrentRoute() -> AVAudioSession.RouteDescription
       func observeRouteChanges(_ handler: @escaping (AVAudioSession.RouteChangeReason) -> Void)
   }
   ```

7. Update AppDelegate.swift with PushKit integration:

   ```swift
   extension AppDelegate: PKPushRegistryDelegate {
       func pushRegistry(_ registry: PKPushRegistry, 
                        didUpdate pushCredentials: PKPushCredentials, 
                        for type: PKPushType)
       
       func pushRegistry(_ registry: PKPushRegistry, 
                        didReceiveIncomingPushWith payload: PKPushPayload, 
                        for type: PKPushType, 
                        completion: @escaping () -> Void)
       
       func pushRegistry(_ registry: PKPushRegistry, 
                        didInvalidatePushTokenFor type: PKPushType)
   }
   ```

8. Create VoiceAIPro/Core/Managers/CallManager.swift:
   - High-level orchestration of TwilioVoiceService and CallKitManager
   - Coordinates WebSocket connection with call lifecycle
   - Updates AppState with call status changes
   - Handles errors and reconnection

IMPORTANT:
- VoIP push notifications MUST report to CallKit within the push handler
- Audio session activation MUST happen in the CallKit delegate
- Always handle call cleanup in all error paths

OUTPUT:
Complete implementation of all Twilio and CallKit integration. The app should be able to make and receive calls (even without AI integration working yet).
```

---

## PROMPT 9: WebSocket Client & Event System

```
Continue building the iOS app. Now implement the WebSocket client for communicating with the bridge server.

CONTEXT:
The iOS app needs two WebSocket connections:
1. Control channel (/ios-client) - for sending configuration and receiving call status
2. Event stream (/events/:callId) - for receiving real-time API events

REQUIREMENTS:

1. Implement VoiceAIPro/Data/Networking/WebSocketClient.swift:

   ```swift
   actor WebSocketClient {
       enum State {
           case disconnected
           case connecting
           case connected
           case error(Error)
       }
       
       private var task: URLSessionWebSocketTask?
       private var session: URLSession
       private let url: URL
       private var pingTask: Task<Void, Never>?
       
       @Published var state: State = .disconnected
       
       init(url: URL)
       
       func connect() async throws
       func disconnect()
       func send(_ message: WebSocketMessage) async throws
       func receive() -> AsyncThrowingStream<WebSocketMessage, Error>
       
       private func startPingLoop()
       private func handleDisconnect(error: Error?)
       private func reconnect() async
   }
   
   enum WebSocketMessage {
       case string(String)
       case data(Data)
       
       var jsonValue: [String: Any]? { ... }
   }
   ```

2. Implement VoiceAIPro/Core/Services/WebSocketService.swift:

   ```swift
   @MainActor
   class WebSocketService: ObservableObject {
       @Published var connectionState: ConnectionState = .disconnected
       @Published var lastError: Error?
       
       private var controlClient: WebSocketClient?
       private var eventClient: WebSocketClient?
       private var messageHandlers: [String: (Any) -> Void] = [:]
       
       enum ConnectionState {
           case disconnected, connecting, connected, reconnecting
       }
       
       // Connection management
       func connect() async throws
       func disconnect()
       
       // Control channel
       func connectControlChannel() async throws
       func sendSessionConfig(_ config: RealtimeConfig) async throws
       func sendCallAction(_ action: CallAction) async throws
       
       // Event streaming
       func connectEventStream(callId: String) async throws
       func disconnectEventStream()
       
       // Message handling
       func onMessage(_ type: String, handler: @escaping (Any) -> Void)
       func removeHandler(for type: String)
       
       // Process incoming messages
       private func handleControlMessage(_ message: WebSocketMessage)
       private func handleEventMessage(_ message: WebSocketMessage)
   }
   
   enum CallAction: Codable {
       case updateConfig(RealtimeConfig)
       case cancelResponse
       case commitAudio
       case clearAudioBuffer
   }
   ```

3. Implement VoiceAIPro/Data/Networking/APIClient.swift:

   ```swift
   actor APIClient {
       static let shared = APIClient()
       
       private let session: URLSession
       private let baseURL: URL
       private let decoder: JSONDecoder
       private let encoder: JSONEncoder
       
       // Generic request method
       func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T
       func requestVoid(_ endpoint: Endpoint) async throws
       
       // Specific endpoints
       func fetchAccessToken(identity: String) async throws -> TokenResponse
       func initiateCall(to: String, promptId: UUID?, config: RealtimeConfig) async throws -> CallResponse
       func endCall(callSid: String) async throws
       func getCallHistory(limit: Int, offset: Int) async throws -> [CallHistoryItem]
       func getCallDetails(callSid: String) async throws -> CallDetails
       func getRecordings(limit: Int, offset: Int) async throws -> [Recording]
       func getRecordingURL(id: UUID) -> URL
       func deleteRecording(id: UUID) async throws
       func getPrompts() async throws -> [Prompt]
       func createPrompt(_ prompt: Prompt) async throws -> Prompt
       func updatePrompt(_ prompt: Prompt) async throws -> Prompt
       func deletePrompt(id: UUID) async throws
       func setDefaultPrompt(id: UUID) async throws
   }
   
   enum Endpoint {
       case token(identity: String)
       case initiateCall(to: String, promptId: UUID?, config: RealtimeConfig)
       case endCall(callSid: String)
       case callHistory(limit: Int, offset: Int)
       case callDetails(callSid: String)
       case recordings(limit: Int, offset: Int)
       case deleteRecording(id: UUID)
       case prompts
       case createPrompt(Prompt)
       case updatePrompt(Prompt)
       case deletePrompt(id: UUID)
       case setDefaultPrompt(id: UUID)
       
       var path: String { ... }
       var method: String { ... }
       var body: Data? { ... }
   }
   ```

4. Create response models in VoiceAIPro/Data/Networking/Responses/:
   - TokenResponse.swift
   - CallResponse.swift
   - CallHistoryItem.swift
   - CallDetails.swift
   - Recording.swift
   - ErrorResponse.swift

5. Implement event processing in VoiceAIPro/Core/Services/EventProcessor.swift:

   ```swift
   @MainActor
   class EventProcessor: ObservableObject {
       @Published var events: [CallEvent] = []
       @Published var currentTranscript: String = ""
       @Published var userTranscript: String = ""
       @Published var aiTranscript: String = ""
       @Published var isAISpeaking: Bool = false
       @Published var isUserSpeaking: Bool = false
       
       private let maxEvents = 1000
       
       func processEvent(_ event: CallEvent) {
           // Add to events list (with max limit)
           // Update state based on event type
           // Update transcripts
       }
       
       func clearEvents()
       
       func exportEvents() -> Data // JSON export
   }
   ```

6. Wire everything together in CallManager:
   - On call start: connect WebSocket, start event stream
   - On config change: send via WebSocket
   - On call end: disconnect, save events locally

OUTPUT:
Complete implementation of all networking components. The WebSocket client should handle reconnection gracefully. The API client should have proper error handling and type-safe responses.
```

---

## PROMPT 10: SwiftData Models & Persistence

```
Continue building the iOS app. Now implement the SwiftData persistence layer.

CONTEXT:
SwiftData is used for local caching and offline access to:
- Call history (synced from server)
- Saved prompts (synced from server)
- Event logs (cached for viewing)
- User preferences (local only)
- Recording metadata (synced from server)

REQUIREMENTS:

1. Implement VoiceAIPro/Data/SwiftData/CallRecord.swift:

   ```swift
   @Model
   final class CallRecord {
       @Attribute(.unique) var id: UUID
       var callSid: String?
       var direction: String // "inbound" | "outbound"
       var phoneNumber: String
       var status: String
       var startedAt: Date
       var endedAt: Date?
       var durationSeconds: Int?
       var promptId: UUID?
       var configSnapshot: Data? // Encoded RealtimeConfig
       var syncedAt: Date?
       
       @Relationship(deleteRule: .cascade, inverse: \EventLogEntry.callRecord)
       var events: [EventLogEntry]?
       
       @Relationship(deleteRule: .cascade, inverse: \TranscriptEntry.callRecord)
       var transcripts: [TranscriptEntry]?
       
       init(from session: CallSession) { ... }
       
       var decodedConfig: RealtimeConfig? { ... }
       var callDirection: CallDirection { ... }
       var callStatus: CallStatus { ... }
   }
   ```

2. Implement VoiceAIPro/Data/SwiftData/EventLogEntry.swift:

   ```swift
   @Model
   final class EventLogEntry {
       @Attribute(.unique) var id: UUID
       var eventType: String
       var direction: String // "incoming" | "outgoing"
       var payload: Data? // JSON payload
       var timestamp: Date
       
       var callRecord: CallRecord?
       
       init(from event: CallEvent) { ... }
       
       var decodedPayload: [String: Any]? { ... }
       var callEventType: CallEvent.EventType? { ... }
   }
   ```

3. Implement VoiceAIPro/Data/SwiftData/SavedPrompt.swift:

   ```swift
   @Model
   final class SavedPrompt {
       @Attribute(.unique) var id: UUID
       var name: String
       var instructions: String
       var voice: String
       var vadConfigData: Data? // Encoded VADConfig
       var isDefault: Bool
       var createdAt: Date
       var updatedAt: Date
       var syncedAt: Date?
       
       init(from prompt: Prompt) { ... }
       
       func toPrompt() -> Prompt { ... }
       
       var decodedVADConfig: VADConfig? { ... }
       var realtimeVoice: RealtimeVoice { ... }
   }
   ```

4. Implement VoiceAIPro/Data/SwiftData/TranscriptEntry.swift:

   ```swift
   @Model
   final class TranscriptEntry {
       @Attribute(.unique) var id: UUID
       var speaker: String // "user" | "assistant"
       var content: String
       var timestampMs: Int?
       var createdAt: Date
       
       var callRecord: CallRecord?
       
       init(speaker: String, content: String, timestampMs: Int?) { ... }
   }
   ```

5. Implement VoiceAIPro/Data/SwiftData/RecordingMetadata.swift:

   ```swift
   @Model
   final class RecordingMetadata {
       @Attribute(.unique) var id: UUID
       var callSessionId: UUID
       var durationSeconds: Int
       var fileSizeBytes: Int64
       var format: String
       var createdAt: Date
       var localPath: String? // If downloaded
       var syncedAt: Date?
       
       init(from recording: Recording) { ... }
       
       var isDownloaded: Bool { localPath != nil }
   }
   ```

6. Implement VoiceAIPro/Data/SwiftData/UserSettings.swift:

   ```swift
   @Model
   final class UserSettings {
       var deviceId: UUID
       var defaultConfigData: Data? // Encoded RealtimeConfig
       var recordingEnabled: Bool
       var eventLoggingEnabled: Bool
       var hapticFeedbackEnabled: Bool
       var lastSyncDate: Date?
       
       static func getOrCreate(context: ModelContext) -> UserSettings { ... }
       
       var defaultConfig: RealtimeConfig { ... }
   }
   ```

7. Create VoiceAIPro/Data/SwiftData/DataManager.swift:

   ```swift
   @MainActor
   class DataManager: ObservableObject {
       let container: ModelContainer
       var context: ModelContext { container.mainContext }
       
       init() throws {
           let schema = Schema([
               CallRecord.self,
               EventLogEntry.self,
               SavedPrompt.self,
               TranscriptEntry.self,
               RecordingMetadata.self,
               UserSettings.self
           ])
           let config = ModelConfiguration(isStoredInMemoryOnly: false)
           container = try ModelContainer(for: schema, configurations: config)
       }
       
       // Call Records
       func saveCallRecord(_ session: CallSession) throws
       func updateCallRecord(_ callSid: String, updates: (inout CallRecord) -> Void) throws
       func getCallRecords(limit: Int, offset: Int) -> [CallRecord]
       func getCallRecord(id: UUID) -> CallRecord?
       func getCallRecord(callSid: String) -> CallRecord?
       
       // Events
       func saveEvents(_ events: [CallEvent], for callSid: String) throws
       func getEvents(for callSid: String) -> [EventLogEntry]
       
       // Prompts
       func savePrompt(_ prompt: Prompt) throws
       func updatePrompt(_ prompt: Prompt) throws
       func deletePrompt(id: UUID) throws
       func getPrompts() -> [SavedPrompt]
       func getDefaultPrompt() -> SavedPrompt?
       func setDefaultPrompt(id: UUID) throws
       
       // Recordings
       func saveRecordingMetadata(_ recording: Recording) throws
       func getRecordings(limit: Int, offset: Int) -> [RecordingMetadata]
       func updateRecordingLocalPath(id: UUID, path: String) throws
       func deleteRecording(id: UUID) throws
       
       // Settings
       func getSettings() -> UserSettings
       func updateSettings(_ updates: (inout UserSettings) -> Void) throws
       
       // Sync
       func syncCallHistory(with serverHistory: [CallHistoryItem]) async throws
       func syncPrompts(with serverPrompts: [Prompt]) async throws
   }
   ```

8. Configure SwiftData in VoiceAIProApp.swift:
   - Create ModelContainer
   - Inject into environment
   - Handle migration if needed

OUTPUT:
Complete implementation of all SwiftData models and the DataManager. Ensure proper relationships, indexes, and query performance. Include migration strategy for future schema changes.
```

---

## PROMPT 11: Dashboard & Dialer Views

```
Continue building the iOS app. Now implement the main Dashboard and Dialer views.

CONTEXT:
- Dashboard: Home screen showing active call status, quick actions, recent calls
- Dialer: Phone number input with prompt selection and call initiation

DESIGN:
- Follow Apple Human Interface Guidelines
- Use SF Symbols for icons
- Support Dark Mode
- Minimum touch targets: 44x44pt

REQUIREMENTS:

1. Implement VoiceAIPro/Features/Dashboard/DashboardView.swift:

   ```swift
   struct DashboardView: View {
       @EnvironmentObject var appState: AppState
       @EnvironmentObject var callManager: CallManager
       @StateObject private var viewModel: DashboardViewModel
       
       var body: some View {
           NavigationStack {
               ScrollView {
                   VStack(spacing: 20) {
                       // Active Call Card (shown when call active)
                       if appState.isCallActive {
                           ActiveCallCard(session: appState.currentCall)
                       }
                       
                       // Quick Dial Section
                       QuickDialSection(onDial: viewModel.quickDial)
                       
                       // Connection Status
                       ConnectionStatusView(state: appState.connectionState)
                       
                       // Recent Calls
                       RecentCallsSection(calls: viewModel.recentCalls)
                       
                       // Current Config Summary
                       ConfigSummaryCard(config: appState.realtimeConfig)
                   }
                   .padding()
               }
               .navigationTitle("VoiceAI Pro")
               .toolbar {
                   ToolbarItem(placement: .topBarTrailing) {
                       NavigationLink(destination: SettingsView()) {
                           Image(systemName: "gear")
                       }
                   }
               }
           }
       }
   }
   ```

2. Implement DashboardViewModel.swift:

   ```swift
   @MainActor
   class DashboardViewModel: ObservableObject {
       @Published var recentCalls: [CallRecord] = []
       @Published var isLoading = false
       
       private let dataManager: DataManager
       private let apiClient: APIClient
       
       func loadRecentCalls()
       func quickDial(_ number: String)
       func syncWithServer() async
   }
   ```

3. Implement supporting views:

   ActiveCallCard.swift:
   ```swift
   struct ActiveCallCard: View {
       let session: CallSession?
       @State private var elapsedTime: TimeInterval = 0
       
       // Shows: phone number, status, duration timer, end call button
       // Animated border/glow effect when active
   }
   ```

   QuickDialSection.swift:
   ```swift
   struct QuickDialSection: View {
       let onDial: (String) -> Void
       @State private var phoneNumber = ""
       
       // Phone number text field with formatting
       // Call button
       // Recent numbers as quick chips
   }
   ```

   ConnectionStatusView.swift:
   ```swift
   struct ConnectionStatusView: View {
       let state: AppState.ConnectionState
       
       // Small indicator: green dot = connected, yellow = connecting, red = error
       // Expandable to show details
   }
   ```

   RecentCallsSection.swift:
   ```swift
   struct RecentCallsSection: View {
       let calls: [CallRecord]
       
       // List of last 5 calls
       // Each row: direction icon, phone number, time ago, duration
       // Tap to see details or redial
   }
   ```

   ConfigSummaryCard.swift:
   ```swift
   struct ConfigSummaryCard: View {
       let config: RealtimeConfig
       
       // Shows current: voice, VAD type, model
       // Tap to go to settings
   }
   ```

4. Implement VoiceAIPro/Features/Dialer/DialerView.swift:

   ```swift
   struct DialerView: View {
       @EnvironmentObject var appState: AppState
       @StateObject private var viewModel: DialerViewModel
       
       var body: some View {
           NavigationStack {
               VStack(spacing: 0) {
                   // Phone Number Display
                   PhoneNumberDisplay(number: $viewModel.phoneNumber)
                   
                   // Prompt Selector
                   PromptSelectorView(
                       selectedPrompt: $viewModel.selectedPrompt,
                       prompts: viewModel.prompts
                   )
                   
                   // Dial Pad
                   DialPadView(onDigit: viewModel.appendDigit,
                              onDelete: viewModel.deleteDigit)
                   
                   // Call Button
                   CallButton(
                       isEnabled: viewModel.canCall,
                       isLoading: viewModel.isInitiating,
                       action: viewModel.initiateCall
                   )
                   .padding()
               }
               .navigationTitle("Dial")
           }
       }
   }
   ```

5. Implement DialerViewModel.swift:

   ```swift
   @MainActor
   class DialerViewModel: ObservableObject {
       @Published var phoneNumber = ""
       @Published var selectedPrompt: SavedPrompt?
       @Published var prompts: [SavedPrompt] = []
       @Published var isInitiating = false
       @Published var error: Error?
       
       var canCall: Bool { ... }
       
       func appendDigit(_ digit: String)
       func deleteDigit()
       func clearNumber()
       func initiateCall() async
       func loadPrompts()
   }
   ```

6. Implement dialer components:

   PhoneNumberDisplay.swift:
   ```swift
   struct PhoneNumberDisplay: View {
       @Binding var number: String
       
       // Large display of formatted phone number
       // Paste button
       // Clear button
   }
   ```

   DialPadView.swift:
   ```swift
   struct DialPadView: View {
       let onDigit: (String) -> Void
       let onDelete: () -> Void
       
       // 3x4 grid of digits (1-9, *, 0, #)
       // Haptic feedback on tap
       // Long press 0 for +
   }
   ```

   PromptSelectorView.swift:
   ```swift
   struct PromptSelectorView: View {
       @Binding var selectedPrompt: SavedPrompt?
       let prompts: [SavedPrompt]
       
       // Horizontal scroll of prompt chips
       // Default prompt highlighted
       // "Custom" option to edit inline
   }
   ```

   CallButton.swift:
   ```swift
   struct CallButton: View {
       let isEnabled: Bool
       let isLoading: Bool
       let action: () async -> Void
       
       // Large green circular button
       // Phone icon
       // Loading spinner when initiating
       // Disabled state styling
   }
   ```

7. Implement phone number formatting utility:
   
   PhoneNumberFormatter.swift:
   ```swift
   struct PhoneNumberFormatter {
       static func format(_ number: String) -> String
       static func unformat(_ number: String) -> String
       static func isValid(_ number: String) -> Bool
   }
   ```

OUTPUT:
Complete implementation of Dashboard and Dialer views with all subcomponents. Views should be responsive, accessible, and follow iOS design conventions. Include proper state management and error handling.
```

---

## PROMPT 12: Active Call & Controls Views

```
Continue building the iOS app. Now implement the Active Call view with real-time controls and visualization.

CONTEXT:
When a call is active, the user needs:
- Visual feedback (waveform, status indicators)
- Call controls (mute, speaker, end)
- Live transcription display
- Access to AI configuration adjustments
- Event log access

REQUIREMENTS:

1. Implement VoiceAIPro/Features/ActiveCall/ActiveCallView.swift:

   ```swift
   struct ActiveCallView: View {
       @EnvironmentObject var appState: AppState
       @EnvironmentObject var callManager: CallManager
       @StateObject private var viewModel: ActiveCallViewModel
       @State private var showingEventLog = false
       @State private var showingConfig = false
       
       var body: some View {
           ZStack {
               // Background gradient based on call status
               CallBackgroundView(status: appState.callStatus)
               
               VStack(spacing: 20) {
                   // Call Info Header
                   CallInfoHeader(
                       phoneNumber: appState.currentCall?.phoneNumber ?? "",
                       status: appState.callStatus,
                       direction: appState.currentCall?.direction ?? .outbound
                   )
                   
                   // Audio Visualization
                   AudioWaveformView(
                       isUserSpeaking: viewModel.isUserSpeaking,
                       isAISpeaking: viewModel.isAISpeaking,
                       userAudioLevel: viewModel.userAudioLevel,
                       aiAudioLevel: viewModel.aiAudioLevel
                   )
                   
                   // Live Transcription
                   TranscriptionView(
                       userTranscript: viewModel.userTranscript,
                       aiTranscript: viewModel.aiTranscript,
                       isUserSpeaking: viewModel.isUserSpeaking,
                       isAISpeaking: viewModel.isAISpeaking
                   )
                   
                   Spacer()
                   
                   // Duration Timer
                   DurationTimerView(startTime: appState.currentCall?.startedAt)
                   
                   // Call Controls
                   CallControlsView(
                       isMuted: $viewModel.isMuted,
                       isSpeakerOn: $viewModel.isSpeakerOn,
                       onMuteToggle: viewModel.toggleMute,
                       onSpeakerToggle: viewModel.toggleSpeaker,
                       onEndCall: viewModel.endCall,
                       onShowConfig: { showingConfig = true },
                       onShowEventLog: { showingEventLog = true }
                   )
               }
               .padding()
           }
           .sheet(isPresented: $showingEventLog) {
               EventLogSheet(events: viewModel.events)
           }
           .sheet(isPresented: $showingConfig) {
               QuickConfigSheet(config: $viewModel.config, onApply: viewModel.applyConfig)
           }
       }
   }
   ```

2. Implement ActiveCallViewModel.swift:

   ```swift
   @MainActor
   class ActiveCallViewModel: ObservableObject {
       @Published var isMuted = false
       @Published var isSpeakerOn = false
       @Published var isUserSpeaking = false
       @Published var isAISpeaking = false
       @Published var userAudioLevel: Float = 0
       @Published var aiAudioLevel: Float = 0
       @Published var userTranscript = ""
       @Published var aiTranscript = ""
       @Published var events: [CallEvent] = []
       @Published var config: RealtimeConfig
       
       private var eventSubscription: AnyCancellable?
       
       init(callManager: CallManager, eventProcessor: EventProcessor) { ... }
       
       func toggleMute()
       func toggleSpeaker()
       func endCall()
       func applyConfig(_ config: RealtimeConfig) async
       
       private func subscribeToEvents()
       private func processEvent(_ event: CallEvent)
   }
   ```

3. Implement visual components:

   CallBackgroundView.swift:
   ```swift
   struct CallBackgroundView: View {
       let status: CallStatus
       
       // Animated gradient background
       // Colors change based on status:
       // - connecting: blue pulse
       // - connected: calm green gradient
       // - ended: gray fade
   }
   ```

   CallInfoHeader.swift:
   ```swift
   struct CallInfoHeader: View {
       let phoneNumber: String
       let status: CallStatus
       let direction: CallDirection
       
       // Direction icon (inbound/outbound arrow)
       // Formatted phone number
       // Status badge with color
   }
   ```

   AudioWaveformView.swift:
   ```swift
   struct AudioWaveformView: View {
       let isUserSpeaking: Bool
       let isAISpeaking: Bool
       let userAudioLevel: Float
       let aiAudioLevel: Float
       
       // Two-sided waveform visualization
       // User audio on left (or top)
       // AI audio on right (or bottom)
       // Animated bars responding to audio levels
       // Different colors for user vs AI
   }
   ```

   TranscriptionView.swift:
   ```swift
   struct TranscriptionView: View {
       let userTranscript: String
       let aiTranscript: String
       let isUserSpeaking: Bool
       let isAISpeaking: Bool
       
       // Chat-bubble style transcript display
       // User bubbles aligned left
       // AI bubbles aligned right
       // Typing indicator when speaking
       // Auto-scroll to bottom
       // Max height with scroll
   }
   ```

   DurationTimerView.swift:
   ```swift
   struct DurationTimerView: View {
       let startTime: Date?
       @State private var duration: TimeInterval = 0
       
       // MM:SS format
       // Updates every second
       // Monospace font for stability
   }
   ```

   CallControlsView.swift:
   ```swift
   struct CallControlsView: View {
       @Binding var isMuted: Bool
       @Binding var isSpeakerOn: Bool
       let onMuteToggle: () -> Void
       let onSpeakerToggle: () -> Void
       let onEndCall: () -> Void
       let onShowConfig: () -> Void
       let onShowEventLog: () -> Void
       
       // Horizontal row of circular buttons:
       // - Mute (mic icon, toggleable)
       // - Speaker (speaker icon, toggleable)
       // - Config (gear icon)
       // - Event Log (list icon)
       // - End Call (red phone down, larger)
   }
   ```

4. Implement sheet views:

   EventLogSheet.swift:
   ```swift
   struct EventLogSheet: View {
       let events: [CallEvent]
       @State private var filter: EventFilter = .all
       
       // Header with close button and filter picker
       // Scrollable list of events
       // Each event: timestamp, type badge, direction, expandable payload
   }
   ```

   QuickConfigSheet.swift:
   ```swift
   struct QuickConfigSheet: View {
       @Binding var config: RealtimeConfig
       let onApply: (RealtimeConfig) async -> Void
       
       // Quick access to common settings:
       // - Voice picker (horizontal scroll)
       // - VAD sensitivity slider
       // - Temperature slider
       // - Apply button
   }
   ```

5. Add haptic feedback throughout:
   - Button presses
   - Speech started/stopped
   - Call connected/ended

OUTPUT:
Complete implementation of the Active Call view and all components. The view should feel polished and responsive. Waveform visualization should be smooth (use displayLink or TimelineView for animation).
```

---

## PROMPT 13: Settings & Configuration Views

```
Continue building the iOS app. Now implement the comprehensive Settings views with all AI configuration options.

CONTEXT:
Settings must expose ALL configurable parameters from the OpenAI Realtime API:
- Model selection
- Voice selection with audio previews
- VAD type and parameters
- Noise reduction
- Transcription model
- Temperature
- Max output tokens
- Recording preferences
- Account settings

REQUIREMENTS:

1. Implement VoiceAIPro/Features/Settings/SettingsView.swift:

   ```swift
   struct SettingsView: View {
       @EnvironmentObject var appState: AppState
       @StateObject private var viewModel: SettingsViewModel
       
       var body: some View {
           NavigationStack {
               List {
                   // AI Configuration Section
                   Section("AI Configuration") {
                       NavigationLink("Model", destination: ModelSelectionView())
                       NavigationLink("Voice", destination: VoiceSelectionView())
                       NavigationLink("Voice Activity Detection", destination: VADConfigView())
                       NavigationLink("Noise Reduction", destination: NoiseReductionView())
                       NavigationLink("Transcription", destination: TranscriptionConfigView())
                       NavigationLink("Response Settings", destination: ResponseSettingsView())
                   }
                   
                   // Recording Section
                   Section("Recording") {
                       Toggle("Enable Call Recording", isOn: $viewModel.recordingEnabled)
                       if viewModel.recordingEnabled {
                           NavigationLink("Recording Settings", destination: RecordingSettingsView())
                       }
                   }
                   
                   // Prompts Section
                   Section("Prompts") {
                       NavigationLink("Manage Prompts", destination: PromptsView())
                   }
                   
                   // App Settings Section
                   Section("App Settings") {
                       Toggle("Event Logging", isOn: $viewModel.eventLoggingEnabled)
                       Toggle("Haptic Feedback", isOn: $viewModel.hapticFeedbackEnabled)
                       NavigationLink("About", destination: AboutView())
                   }
                   
                   // Server Configuration (Debug)
                   Section("Server") {
                       HStack {
                           Text("Server URL")
                           Spacer()
                           Text(viewModel.serverURL)
                               .foregroundStyle(.secondary)
                       }
                       NavigationLink("Connection Test", destination: ConnectionTestView())
                   }
               }
               .navigationTitle("Settings")
           }
       }
   }
   ```

2. Implement VoiceAIPro/Features/Settings/VoiceSelectionView.swift:

   ```swift
   struct VoiceSelectionView: View {
       @EnvironmentObject var appState: AppState
       @State private var playingVoice: RealtimeVoice?
       
       let columns = [GridItem(.adaptive(minimum: 100))]
       
       var body: some View {
           ScrollView {
               LazyVGrid(columns: columns, spacing: 16) {
                   ForEach(RealtimeVoice.allCases, id: \.self) { voice in
                       VoiceCard(
                           voice: voice,
                           isSelected: appState.realtimeConfig.voice == voice,
                           isPlaying: playingVoice == voice,
                           onSelect: { selectVoice(voice) },
                           onPreview: { previewVoice(voice) }
                       )
                   }
               }
               .padding()
           }
           .navigationTitle("Voice")
           .navigationBarTitleDisplayMode(.large)
       }
       
       func selectVoice(_ voice: RealtimeVoice) { ... }
       func previewVoice(_ voice: RealtimeVoice) async { ... }
   }
   
   struct VoiceCard: View {
       let voice: RealtimeVoice
       let isSelected: Bool
       let isPlaying: Bool
       let onSelect: () -> Void
       let onPreview: () -> Void
       
       // Card with voice name
       // Description of voice character
       // Checkmark if selected
       // Play button for preview
       // Animated indicator when playing
   }
   ```

3. Implement VoiceAIPro/Features/Settings/VADConfigView.swift:

   ```swift
   struct VADConfigView: View {
       @EnvironmentObject var appState: AppState
       @State private var vadType: VADType = .serverVAD
       @State private var serverVADParams: ServerVADParams = .default
       @State private var semanticVADParams: SemanticVADParams = .default
       
       enum VADType: String, CaseIterable {
           case serverVAD = "Server VAD"
           case semanticVAD = "Semantic VAD"
           case disabled = "Disabled"
       }
       
       var body: some View {
           Form {
               // VAD Type Picker
               Section {
                   Picker("Detection Type", selection: $vadType) {
                       ForEach(VADType.allCases, id: \.self) { type in
                           Text(type.rawValue).tag(type)
                       }
                   }
                   .pickerStyle(.segmented)
               } footer: {
                   Text(vadTypeDescription)
               }
               
               // Server VAD Parameters
               if vadType == .serverVAD {
                   Section("Server VAD Settings") {
                       VStack(alignment: .leading) {
                           Text("Threshold: \(serverVADParams.threshold, specifier: "%.2f")")
                           Slider(value: $serverVADParams.threshold, in: 0...1, step: 0.05)
                       }
                       
                       VStack(alignment: .leading) {
                           Text("Prefix Padding: \(serverVADParams.prefixPaddingMs)ms")
                           Slider(value: .init(get: { Double(serverVADParams.prefixPaddingMs) },
                                              set: { serverVADParams.prefixPaddingMs = Int($0) }),
                                  in: 100...1000, step: 50)
                       }
                       
                       VStack(alignment: .leading) {
                           Text("Silence Duration: \(serverVADParams.silenceDurationMs)ms")
                           Slider(value: .init(get: { Double(serverVADParams.silenceDurationMs) },
                                              set: { serverVADParams.silenceDurationMs = Int($0) }),
                                  in: 200...2000, step: 100)
                       }
                       
                       Toggle("Create Response", isOn: $serverVADParams.createResponse)
                       Toggle("Allow Interruption", isOn: $serverVADParams.interruptResponse)
                   }
               }
               
               // Semantic VAD Parameters
               if vadType == .semanticVAD {
                   Section("Semantic VAD Settings") {
                       Picker("Eagerness", selection: $semanticVADParams.eagerness) {
                           ForEach(SemanticVADParams.Eagerness.allCases, id: \.self) { level in
                               Text(level.rawValue.capitalized).tag(level)
                           }
                       }
                       
                       Toggle("Create Response", isOn: $semanticVADParams.createResponse)
                       Toggle("Allow Interruption", isOn: $semanticVADParams.interruptResponse)
                   } footer: {
                       Text(eagernessDescription)
                   }
               }
           }
           .navigationTitle("Voice Activity Detection")
           .onChange(of: vadType) { updateConfig() }
           .onChange(of: serverVADParams) { updateConfig() }
           .onChange(of: semanticVADParams) { updateConfig() }
       }
       
       var vadTypeDescription: String { ... }
       var eagernessDescription: String { ... }
       func updateConfig() { ... }
   }
   ```

4. Implement VoiceAIPro/Features/Settings/NoiseReductionView.swift:

   ```swift
   struct NoiseReductionView: View {
       @EnvironmentObject var appState: AppState
       @State private var noiseReduction: NoiseReduction?
       
       var body: some View {
           Form {
               Section {
                   Picker("Noise Reduction", selection: $noiseReduction) {
                       Text("Off").tag(nil as NoiseReduction?)
                       Text("Near Field").tag(NoiseReduction.nearField as NoiseReduction?)
                       Text("Far Field").tag(NoiseReduction.farField as NoiseReduction?)
                   }
                   .pickerStyle(.inline)
               } footer: {
                   Text(noiseReductionDescription)
               }
           }
           .navigationTitle("Noise Reduction")
           .onChange(of: noiseReduction) { updateConfig() }
       }
       
       var noiseReductionDescription: String {
           switch noiseReduction {
           case .nearField: return "Best for close-range audio like phone calls or headsets."
           case .farField: return "Best for distant audio sources or speakerphone."
           case nil: return "No noise reduction applied."
           }
       }
   }
   ```

5. Implement additional settings views:

   ModelSelectionView.swift - picker for gpt-realtime vs gpt-realtime-mini
   TranscriptionConfigView.swift - picker for whisper-1 vs gpt-4o-transcribe
   ResponseSettingsView.swift - temperature slider, max tokens stepper
   RecordingSettingsView.swift - format, quality options

6. Implement SettingsViewModel.swift:

   ```swift
   @MainActor
   class SettingsViewModel: ObservableObject {
       @Published var recordingEnabled: Bool
       @Published var eventLoggingEnabled: Bool
       @Published var hapticFeedbackEnabled: Bool
       @Published var serverURL: String
       
       private let dataManager: DataManager
       
       init(dataManager: DataManager) { ... }
       
       func saveSettings() { ... }
       func resetToDefaults() { ... }
   }
   ```

OUTPUT:
Complete implementation of all Settings views. Each configuration option must have clear labels, descriptions, and appropriate input controls. Changes should persist immediately.
```

---

## PROMPT 14: Event Log & History Views

```
Continue building the iOS app. Now implement the Event Log and Call History views.

CONTEXT:
- Event Log: Real-time display of all OpenAI Realtime API events for debugging/monitoring
- Call History: List of past calls with ability to view details, transcripts, and recordings

REQUIREMENTS:

1. Implement VoiceAIPro/Features/EventLog/EventLogView.swift:

   ```swift
   struct EventLogView: View {
       @StateObject private var viewModel: EventLogViewModel
       @State private var selectedEvent: CallEvent?
       @State private var filter: EventFilter = .all
       @State private var isAutoScrollEnabled = true
       
       var body: some View {
           NavigationStack {
               VStack(spacing: 0) {
                   // Filter Bar
                   EventFilterBar(filter: $filter, eventCounts: viewModel.eventCounts)
                   
                   // Event List
                   ScrollViewReader { proxy in
                       List(viewModel.filteredEvents) { event in
                           EventLogRow(event: event, isExpanded: selectedEvent?.id == event.id)
                               .onTapGesture { toggleEventSelection(event) }
                               .id(event.id)
                       }
                       .listStyle(.plain)
                       .onChange(of: viewModel.events.count) {
                           if isAutoScrollEnabled, let lastEvent = viewModel.events.last {
                               withAnimation {
                                   proxy.scrollTo(lastEvent.id, anchor: .bottom)
                               }
                           }
                       }
                   }
               }
               .navigationTitle("Event Log")
               .toolbar {
                   ToolbarItem(placement: .topBarTrailing) {
                       Menu {
                           Toggle("Auto-Scroll", isOn: $isAutoScrollEnabled)
                           Divider()
                           Button("Clear Events", action: viewModel.clearEvents)
                           Button("Export Events", action: viewModel.exportEvents)
                       } label: {
                           Image(systemName: "ellipsis.circle")
                       }
                   }
               }
           }
       }
   }
   ```

2. Implement EventLogViewModel.swift:

   ```swift
   @MainActor
   class EventLogViewModel: ObservableObject {
       @Published var events: [CallEvent] = []
       @Published var eventCounts: [CallEvent.EventType: Int] = [:]
       
       var filteredEvents: [CallEvent] { ... }
       
       private var subscription: AnyCancellable?
       
       init(eventProcessor: EventProcessor) {
           // Subscribe to event stream
       }
       
       func clearEvents() { ... }
       func exportEvents() { ... }
   }
   ```

3. Implement event log components:

   EventFilterBar.swift:
   ```swift
   struct EventFilterBar: View {
       @Binding var filter: EventFilter
       let eventCounts: [CallEvent.EventType: Int]
       
       // Horizontal scroll of filter chips
       // "All" + categories (Session, Audio, Transcription, Response, Error)
       // Each chip shows count badge
   }
   
   enum EventFilter: CaseIterable {
       case all
       case session
       case audio
       case transcription
       case response
       case error
       
       var eventTypes: [CallEvent.EventType]? { ... }
   }
   ```

   EventLogRow.swift:
   ```swift
   struct EventLogRow: View {
       let event: CallEvent
       let isExpanded: Bool
       
       var body: some View {
           VStack(alignment: .leading, spacing: 8) {
               HStack {
                   // Direction indicator (arrow in/out)
                   DirectionIndicator(direction: event.direction)
                   
                   // Event type badge (colored)
                   EventTypeBadge(type: event.eventType)
                   
                   Spacer()
                   
                   // Timestamp
                   Text(event.timestamp, style: .time)
                       .font(.caption)
                       .foregroundStyle(.secondary)
               }
               
               // Expanded payload view
               if isExpanded, let payload = event.payload {
                   PayloadView(payload: payload)
                       .transition(.opacity)
               }
           }
           .padding(.vertical, 4)
       }
   }
   ```

   EventTypeBadge.swift:
   ```swift
   struct EventTypeBadge: View {
       let type: CallEvent.EventType
       
       // Colored pill with short event name
       // Color based on category:
       // - Session: blue
       // - Audio: green
       // - Transcription: orange
       // - Response: purple
       // - Error: red
   }
   ```

   PayloadView.swift:
   ```swift
   struct PayloadView: View {
       let payload: String
       
       // Pretty-printed JSON view
       // Syntax highlighting
       // Copy button
   }
   ```

4. Implement VoiceAIPro/Features/CallHistory/CallHistoryView.swift:

   ```swift
   struct CallHistoryView: View {
       @StateObject private var viewModel: CallHistoryViewModel
       
       var body: some View {
           NavigationStack {
               List {
                   ForEach(viewModel.groupedCalls, id: \.date) { group in
                       Section(header: Text(group.date, style: .date)) {
                           ForEach(group.calls) { call in
                               NavigationLink(destination: CallDetailView(call: call)) {
                                   CallHistoryRow(call: call)
                               }
                           }
                           .onDelete { indexSet in
                               viewModel.deleteCalls(at: indexSet, in: group)
                           }
                       }
                   }
                   
                   // Load more button
                   if viewModel.hasMoreCalls {
                       Button("Load More") {
                           Task { await viewModel.loadMoreCalls() }
                       }
                   }
               }
               .navigationTitle("History")
               .refreshable {
                   await viewModel.refresh()
               }
           }
       }
   }
   ```

5. Implement CallHistoryViewModel.swift:

   ```swift
   @MainActor
   class CallHistoryViewModel: ObservableObject {
       @Published var calls: [CallRecord] = []
       @Published var isLoading = false
       @Published var hasMoreCalls = true
       
       var groupedCalls: [CallGroup] { ... }
       
       func loadCalls() async { ... }
       func loadMoreCalls() async { ... }
       func refresh() async { ... }
       func deleteCalls(at: IndexSet, in: CallGroup) { ... }
   }
   
   struct CallGroup {
       let date: Date
       let calls: [CallRecord]
   }
   ```

6. Implement CallHistoryRow.swift:

   ```swift
   struct CallHistoryRow: View {
       let call: CallRecord
       
       // Direction icon (incoming/outgoing arrow, colored)
       // Phone number (formatted)
       // Time
       // Duration badge
       // Status indicator if failed
   }
   ```

7. Implement CallDetailView.swift:

   ```swift
   struct CallDetailView: View {
       let call: CallRecord
       @StateObject private var viewModel: CallDetailViewModel
       
       var body: some View {
           ScrollView {
               VStack(spacing: 20) {
                   // Call Info Card
                   CallInfoCard(call: call)
                   
                   // Transcript Section
                   if !viewModel.transcripts.isEmpty {
                       TranscriptSection(transcripts: viewModel.transcripts)
                   }
                   
                   // Recording Section
                   if let recording = viewModel.recording {
                       RecordingSection(recording: recording)
                   }
                   
                   // Events Section
                   EventsSummarySection(events: viewModel.events)
                   
                   // Config Section
                   if let config = call.decodedConfig {
                       ConfigSection(config: config)
                   }
               }
               .padding()
           }
           .navigationTitle("Call Details")
           .toolbar {
               ToolbarItem(placement: .topBarTrailing) {
                   ShareLink(item: viewModel.shareableData)
               }
           }
       }
   }
   ```

8. Implement supporting detail views:

   CallInfoCard.swift - phone number, direction, duration, status, timestamps
   TranscriptSection.swift - chat-bubble style transcript display
   EventsSummarySection.swift - event counts by type, link to full log
   ConfigSection.swift - shows config used for this call

OUTPUT:
Complete implementation of Event Log and Call History features. Event log should update in real-time during calls. Call history should support pagination and offline viewing of cached data.
```

---

## PROMPT 15: Recordings & Prompts Management

```
Continue building the iOS app. Now implement the Recordings viewer and Prompts management features.

CONTEXT:
- Recordings: Browse, play, and manage call recordings with transcript view
- Prompts: Create, edit, delete saved prompts with all configuration options

REQUIREMENTS:

1. Implement VoiceAIPro/Features/Recordings/RecordingsView.swift:

   ```swift
   struct RecordingsView: View {
       @StateObject private var viewModel: RecordingsViewModel
       @State private var selectedRecording: RecordingMetadata?
       
       var body: some View {
           NavigationStack {
               List {
                   ForEach(viewModel.recordings) { recording in
                       RecordingRow(recording: recording)
                           .onTapGesture {
                               selectedRecording = recording
                           }
                   }
                   .onDelete(perform: viewModel.deleteRecordings)
                   
                   if viewModel.hasMore {
                       ProgressView()
                           .onAppear { Task { await viewModel.loadMore() } }
                   }
               }
               .navigationTitle("Recordings")
               .refreshable { await viewModel.refresh() }
               .sheet(item: $selectedRecording) { recording in
                   RecordingPlayerSheet(recording: recording)
               }
           }
       }
   }
   ```

2. Implement RecordingsViewModel.swift:

   ```swift
   @MainActor
   class RecordingsViewModel: ObservableObject {
       @Published var recordings: [RecordingMetadata] = []
       @Published var isLoading = false
       @Published var hasMore = true
       
       private var offset = 0
       private let limit = 20
       
       func loadRecordings() async { ... }
       func loadMore() async { ... }
       func refresh() async { ... }
       func deleteRecordings(at indexSet: IndexSet) { ... }
       func downloadRecording(_ recording: RecordingMetadata) async throws -> URL { ... }
   }
   ```

3. Implement RecordingRow.swift:

   ```swift
   struct RecordingRow: View {
       let recording: RecordingMetadata
       
       // Phone number (from associated call)
       // Date/time
       // Duration
       // File size
       // Download status indicator
   }
   ```

4. Implement RecordingPlayerSheet.swift:

   ```swift
   struct RecordingPlayerSheet: View {
       let recording: RecordingMetadata
       @StateObject private var player: AudioPlayerViewModel
       @State private var showTranscript = false
       
       var body: some View {
           NavigationStack {
               VStack(spacing: 20) {
                   // Recording Info
                   RecordingInfoHeader(recording: recording)
                   
                   // Waveform Visualization
                   WaveformView(samples: player.waveformSamples, 
                               currentPosition: player.currentPosition,
                               onSeek: player.seek)
                   
                   // Time Display
                   HStack {
                       Text(player.currentTime)
                       Spacer()
                       Text(player.duration)
                   }
                   .font(.caption.monospacedDigit())
                   .foregroundStyle(.secondary)
                   
                   // Playback Controls
                   PlaybackControls(
                       isPlaying: player.isPlaying,
                       onPlayPause: player.togglePlayPause,
                       onRewind: { player.skip(seconds: -15) },
                       onForward: { player.skip(seconds: 15) },
                       playbackSpeed: $player.playbackSpeed
                   )
                   
                   // Transcript Toggle
                   if hasTranscript {
                       Toggle("Show Transcript", isOn: $showTranscript)
                   }
                   
                   if showTranscript {
                       TranscriptPlayerView(
                           transcripts: player.transcripts,
                           currentTime: player.currentTimeMs,
                           onSeek: player.seekToTranscript
                       )
                   }
                   
                   Spacer()
               }
               .padding()
               .navigationTitle("Recording")
               .navigationBarTitleDisplayMode(.inline)
               .toolbar {
                   ToolbarItem(placement: .topBarLeading) {
                       Button("Done") { dismiss() }
                   }
                   ToolbarItem(placement: .topBarTrailing) {
                       ShareLink(item: player.shareURL)
                   }
               }
           }
       }
   }
   ```

5. Implement AudioPlayerViewModel.swift:

   ```swift
   @MainActor
   class AudioPlayerViewModel: ObservableObject {
       @Published var isPlaying = false
       @Published var currentPosition: Double = 0
       @Published var waveformSamples: [Float] = []
       @Published var playbackSpeed: Double = 1.0
       @Published var transcripts: [TranscriptEntry] = []
       
       private var player: AVAudioPlayer?
       private var timer: Timer?
       
       var currentTime: String { ... }
       var duration: String { ... }
       var currentTimeMs: Int { ... }
       var shareURL: URL { ... }
       
       init(recordingURL: URL) { ... }
       
       func togglePlayPause() { ... }
       func skip(seconds: Double) { ... }
       func seek(to position: Double) { ... }
       func seekToTranscript(_ transcript: TranscriptEntry) { ... }
       
       private func generateWaveform() async { ... }
       private func loadTranscripts() async { ... }
   }
   ```

6. Implement VoiceAIPro/Features/Prompts/PromptsView.swift:

   ```swift
   struct PromptsView: View {
       @StateObject private var viewModel: PromptsViewModel
       @State private var showingEditor = false
       @State private var editingPrompt: SavedPrompt?
       
       var body: some View {
           NavigationStack {
               List {
                   ForEach(viewModel.prompts) { prompt in
                       PromptRow(prompt: prompt, isDefault: prompt.isDefault)
                           .swipeActions(edge: .leading) {
                               Button("Default") {
                                   viewModel.setDefault(prompt)
                               }
                               .tint(.blue)
                           }
                           .swipeActions(edge: .trailing) {
                               Button("Delete", role: .destructive) {
                                   viewModel.delete(prompt)
                               }
                               Button("Edit") {
                                   editingPrompt = prompt
                               }
                           }
                   }
               }
               .navigationTitle("Prompts")
               .toolbar {
                   ToolbarItem(placement: .topBarTrailing) {
                       Button(action: { showingEditor = true }) {
                           Image(systemName: "plus")
                       }
                   }
               }
               .sheet(isPresented: $showingEditor) {
                   PromptEditorView(onSave: viewModel.createPrompt)
               }
               .sheet(item: $editingPrompt) { prompt in
                   PromptEditorView(prompt: prompt, onSave: viewModel.updatePrompt)
               }
           }
       }
   }
   ```

7. Implement PromptsViewModel.swift:

   ```swift
   @MainActor
   class PromptsViewModel: ObservableObject {
       @Published var prompts: [SavedPrompt] = []
       
       func loadPrompts() async { ... }
       func createPrompt(_ prompt: Prompt) async { ... }
       func updatePrompt(_ prompt: Prompt) async { ... }
       func delete(_ prompt: SavedPrompt) { ... }
       func setDefault(_ prompt: SavedPrompt) { ... }
   }
   ```

8. Implement PromptRow.swift:

   ```swift
   struct PromptRow: View {
       let prompt: SavedPrompt
       let isDefault: Bool
       
       // Prompt name
       // Voice badge
       // VAD type badge
       // Default indicator star
       // Preview of instructions (truncated)
   }
   ```

9. Implement PromptEditorView.swift:

   ```swift
   struct PromptEditorView: View {
       var prompt: SavedPrompt?
       let onSave: (Prompt) async -> Void
       
       @State private var name = ""
       @State private var instructions = ""
       @State private var voice: RealtimeVoice = .marin
       @State private var vadConfig: VADConfig = .serverVAD()
       
       @Environment(\.dismiss) private var dismiss
       
       var body: some View {
           NavigationStack {
               Form {
                   Section("Basic Info") {
                       TextField("Prompt Name", text: $name)
                   }
                   
                   Section("Instructions") {
                       TextEditor(text: $instructions)
                           .frame(minHeight: 150)
                   } footer: {
                       Text("These instructions guide the AI's behavior and responses.")
                   }
                   
                   Section("Voice") {
                       Picker("Voice", selection: $voice) {
                           ForEach(RealtimeVoice.allCases, id: \.self) { voice in
                               Text(voice.rawValue.capitalized).tag(voice)
                           }
                       }
                   }
                   
                   Section("Voice Activity Detection") {
                       VADConfigPicker(config: $vadConfig)
                   }
               }
               .navigationTitle(prompt == nil ? "New Prompt" : "Edit Prompt")
               .navigationBarTitleDisplayMode(.inline)
               .toolbar {
                   ToolbarItem(placement: .topBarLeading) {
                       Button("Cancel") { dismiss() }
                   }
                   ToolbarItem(placement: .topBarTrailing) {
                       Button("Save") {
                           Task {
                               await save()
                               dismiss()
                           }
                       }
                       .disabled(name.isEmpty || instructions.isEmpty)
                   }
               }
           }
           .onAppear { loadPromptIfEditing() }
       }
   }
   ```

OUTPUT:
Complete implementation of Recordings and Prompts features. The audio player should support background playback and show waveform visualization. Prompt editor should include all configurable options.
```

---

## PROMPT 16: Integration Testing & Polish

```
Final prompt. Now integrate all components, add final polish, and ensure everything works together.

CONTEXT:
All individual components have been built. Now:
1. Wire everything together in the main app
2. Add loading states and error handling UI
3. Implement proper navigation flow
4. Add accessibility labels
5. Test the complete flow

REQUIREMENTS:

1. Update VoiceAIProApp.swift to properly initialize all dependencies:

   ```swift
   @main
   struct VoiceAIProApp: App {
       @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
       
       @StateObject private var appState = AppState()
       @StateObject private var callManager: CallManager
       @StateObject private var webSocketService: WebSocketService
       @StateObject private var dataManager: DataManager
       @StateObject private var eventProcessor: EventProcessor
       
       init() {
           // Initialize all dependencies in correct order
           // Wire up dependencies
           // Configure appearance
       }
       
       var body: some Scene {
           WindowGroup {
               ContentView()
                   .environmentObject(appState)
                   .environmentObject(callManager)
                   .environmentObject(webSocketService)
                   .environmentObject(dataManager)
                   .environmentObject(eventProcessor)
                   .modelContainer(dataManager.container)
           }
       }
   }
   ```

2. Implement ContentView.swift with TabView and proper navigation:

   ```swift
   struct ContentView: View {
       @EnvironmentObject var appState: AppState
       @State private var selectedTab = 0
       
       var body: some View {
           ZStack {
               TabView(selection: $selectedTab) {
                   DashboardView()
                       .tabItem { Label("Home", systemImage: "house") }
                       .tag(0)
                   
                   DialerView()
                       .tabItem { Label("Dial", systemImage: "phone") }
                       .tag(1)
                   
                   CallHistoryView()
                       .tabItem { Label("History", systemImage: "clock") }
                       .tag(2)
                   
                   RecordingsView()
                       .tabItem { Label("Recordings", systemImage: "waveform") }
                       .tag(3)
                   
                   SettingsView()
                       .tabItem { Label("Settings", systemImage: "gear") }
                       .tag(4)
               }
               
               // Full-screen overlay for active call
               if appState.isCallActive {
                   ActiveCallView()
                       .transition(.move(edge: .bottom))
               }
           }
           .animation(.spring(), value: appState.isCallActive)
       }
   }
   ```

3. Implement global error handling:

   ErrorBannerView.swift:
   ```swift
   struct ErrorBannerView: View {
       let error: AppError
       let onDismiss: () -> Void
       let onRetry: (() -> Void)?
       
       // Slide-down banner from top
       // Error message
       // Dismiss button
       // Retry button if applicable
   }
   ```

   ErrorHandling.swift:
   ```swift
   enum AppError: LocalizedError {
       case networkError(underlying: Error)
       case twilioError(code: Int, message: String)
       case openAIError(message: String)
       case audioError(message: String)
       case storageError(message: String)
       
       var errorDescription: String? { ... }
       var recoverySuggestion: String? { ... }
   }
   ```

4. Add loading states throughout:

   LoadingOverlay.swift:
   ```swift
   struct LoadingOverlay: View {
       let message: String
       
       // Centered overlay with blur background
       // Spinner
       // Message text
   }
   ```

   EmptyStateView.swift:
   ```swift
   struct EmptyStateView: View {
       let icon: String
       let title: String
       let message: String
       let action: (() -> Void)?
       let actionTitle: String?
       
       // Centered content
       // Large icon
       // Title and message
       // Optional action button
   }
   ```

5. Add accessibility throughout:
   - All interactive elements have accessibility labels
   - Voice-over support
   - Dynamic type support
   - Reduce motion support

6. Implement onboarding (if first launch):

   OnboardingView.swift:
   ```swift
   struct OnboardingView: View {
       // Welcome screen
       // Feature highlights
       // Permissions requests (microphone, push notifications)
       // Server URL configuration (if customizable)
   }
   ```

7. Create a comprehensive CallManager that orchestrates everything:

   ```swift
   @MainActor
   class CallManager: ObservableObject {
       @Published var currentCall: CallSession?
       @Published var callState: CallState = .idle
       
       private let twilioService: TwilioVoiceService
       private let webSocketService: WebSocketService
       private let callKitManager: CallKitManager
       private let dataManager: DataManager
       private let eventProcessor: EventProcessor
       
       enum CallState {
           case idle
           case initiating
           case ringing
           case connecting
           case connected
           case reconnecting
           case ended
           case failed(Error)
       }
       
       // Outgoing call flow
       func initiateCall(to number: String, with config: RealtimeConfig) async throws {
           // 1. Validate phone number
           // 2. Get/refresh Twilio token
           // 3. Create call session locally
           // 4. Connect WebSocket
           // 5. Send session config
           // 6. Initiate Twilio call
           // 7. Wait for connection
           // 8. Update state throughout
       }
       
       // Incoming call flow
       func handleIncomingCall(_ invite: TVOCallInvite) async throws {
           // 1. Report to CallKit
           // 2. Create call session locally
           // 3. Wait for user to accept
           // 4. Connect WebSocket
           // 5. Accept Twilio call
           // 6. Update state
       }
       
       func endCall() async {
           // 1. End Twilio call
           // 2. Disconnect WebSocket
           // 3. Finalize recording
           // 4. Save call record
           // 5. Clean up state
       }
       
       func updateConfig(_ config: RealtimeConfig) async throws {
           // Send updated config via WebSocket
       }
       
       // Private helpers
       private func setupEventHandlers()
       private func handleTwilioEvent(_ event: TwilioEvent)
       private func handleWebSocketEvent(_ event: CallEvent)
       private func handleError(_ error: Error)
   }
   ```

8. Add unit test targets and UI test targets:
   - Test audio conversion
   - Test phone number formatting
   - Test data model encoding/decoding
   - UI tests for critical flows

9. Ensure Info.plist has all required entries:
   - NSMicrophoneUsageDescription
   - UIBackgroundModes (voip, audio)
   - Required device capabilities

10. Add app icon and launch screen

OUTPUT:
Complete final integration with all components working together. The app should:
- Launch and display dashboard
- Connect to server and show status
- Allow dialing a number with custom prompt
- Handle incoming calls with push notifications
- Display active call with live transcription
- Save recordings and transcripts
- Show complete call history
- Allow full configuration of AI parameters

Provide any final files needed to make the app fully functional.
```

---

## Appendix: Checklist for Assistant

Before responding to each prompt, verify:

- [ ] I understand the complete system architecture
- [ ] I know the exact API endpoints and event types
- [ ] I will use production-ready code only
- [ ] I will not use placeholder comments or mock data
- [ ] I will handle all error cases
- [ ] I will follow Swift/Node.js best practices
- [ ] I will include proper documentation
- [ ] My code will compile and run

When implementing:

- [ ] Each function is fully implemented
- [ ] All imports are included
- [ ] Error handling is comprehensive
- [ ] Types are properly defined
- [ ] Async/await is used correctly
- [ ] Memory management is proper (no retain cycles)
- [ ] Thread safety is considered

---

*End of Sequential Prompts Document*
