# VoiceAI Pro: Bidirectional AI Voice Calling Application

## Technical Specification Document
**Version:** 1.0.0  
**Date:** December 31, 2025  
**Platform:** iOS 17+ / WebSocket Server (Node.js)

---

## 1. Executive Summary

VoiceAI Pro is a production-grade iOS application that enables bidirectional speech-to-speech AI conversations over real phone calls. The system integrates OpenAI's Realtime API (GA model `gpt-realtime`) with Twilio's Programmable Voice SDK to create a seamless voice calling experience where an AI agent can handle both incoming and outgoing PSTN calls.

### Core Value Proposition
- **Outgoing Calls:** User initiates calls to any phone number; AI agent conducts the conversation
- **Incoming Calls:** AI agent answers calls on user's behalf with customizable prompts
- **Real-Time Configuration:** Full control over VAD, voices, noise reduction, and conversation parameters
- **Complete Audit Trail:** Event logging, call recordings, and conversation history

---

## 2. System Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              iOS Application                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │   SwiftUI   │  │   Twilio    │  │  WebSocket  │  │   Local Storage     │ │
│  │   Views     │◄─┤   Voice     │◄─┤   Client    │  │   (SwiftData)       │ │
│  │             │  │   SDK       │  │             │  │                     │ │
│  └─────────────┘  └──────┬──────┘  └──────┬──────┘  └─────────────────────┘ │
└──────────────────────────┼────────────────┼─────────────────────────────────┘
                           │                │
                           ▼                ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                         WebSocket Bridge Server (Node.js)                    │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────────────────────┐  │
│  │  Twilio Media  │  │  OpenAI RT     │  │  Audio Bridge                  │  │
│  │  Streams       │◄─┤  WebSocket     │◄─┤  (μ-law ↔ PCM16 @ 24kHz)      │  │
│  │  (μ-law 8kHz)  │  │  (PCM16 24kHz) │  │                                │  │
│  └────────────────┘  └────────────────┘  └────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────┘
                           │                │
                           ▼                ▼
              ┌────────────────────┐  ┌────────────────────┐
              │   Twilio Cloud     │  │   OpenAI Realtime  │
              │   (PSTN Gateway)   │  │   API (gpt-realtime)│
              └────────────────────┘  └────────────────────┘
```

### 2.2 Component Breakdown

| Component | Technology | Responsibility |
|-----------|------------|----------------|
| iOS UI Layer | SwiftUI + UIKit | User interface, configuration, call controls |
| Twilio Voice SDK | TwilioVoice 6.13.x | VoIP signaling, audio capture/playback |
| WebSocket Client | URLSessionWebSocketTask | Real-time communication with bridge server |
| Local Persistence | SwiftData | Call history, saved prompts, recordings metadata |
| Bridge Server | Node.js + ws | Audio bridging, format conversion, event relay |
| OpenAI Integration | WebSocket | Realtime API connection, session management |
| Database | Railway PostgreSQL | Persistent storage for recordings, logs, prompts |

---

## 3. OpenAI Realtime API Specification

### 3.1 Connection Details

```javascript
// WebSocket Connection URL
const OPENAI_REALTIME_URL = "wss://api.openai.com/v1/realtime?model=gpt-realtime";

// Authentication Header
headers: {
  "Authorization": "Bearer " + OPENAI_API_KEY
}
```

### 3.2 Session Configuration Schema

```typescript
interface RealtimeSessionConfig {
  type: "realtime";
  model: "gpt-realtime" | "gpt-realtime-mini";
  instructions: string;
  
  audio: {
    input: {
      format: {
        type: "audio/pcm";
        rate: 24000;
      };
      transcription: {
        model: "whisper-1" | "gpt-4o-transcribe";
      } | null;
      noise_reduction: {
        type: "near_field" | "far_field";
      } | null;
      turn_detection: ServerVADConfig | SemanticVADConfig | null;
    };
    output: {
      format: {
        type: "audio/pcm";
        rate: 24000;
      };
      voice: VoiceType;
      speed: number; // 0.25 - 4.0, default 1.0
    };
  };
  
  tools: Tool[];
  tool_choice: "auto" | "none" | "required";
  temperature: number; // 0.6 - 1.2
  max_output_tokens: number | "inf";
}
```

### 3.3 Voice Activity Detection (VAD) Configuration

#### Server VAD (Default)
```typescript
interface ServerVADConfig {
  type: "server_vad";
  threshold: number;           // 0.0 - 1.0, default 0.5
  prefix_padding_ms: number;   // default 300
  silence_duration_ms: number; // default 500
  idle_timeout_ms: number | null;
  create_response: boolean;    // default true
  interrupt_response: boolean; // default true
}
```

#### Semantic VAD
```typescript
interface SemanticVADConfig {
  type: "semantic_vad";
  eagerness: "low" | "medium" | "high" | "auto"; // default "auto"
  create_response: boolean;
  interrupt_response: boolean;
}
```

### 3.4 Available Voices

| Voice ID | Description | Recommended Use |
|----------|-------------|-----------------|
| `marin` | Professional, clear | **Best for assistants** |
| `cedar` | Natural, conversational | **Best for support agents** |
| `alloy` | Neutral, balanced | General purpose |
| `echo` | Warm, engaging | Customer service |
| `shimmer` | Energetic, expressive | Sales, enthusiasm |
| `ash` | Confident, assertive | Business contexts |
| `ballad` | Storytelling tone | Narratives |
| `coral` | Friendly, approachable | Casual interactions |
| `sage` | Wise, thoughtful | Advisory roles |
| `verse` | Dramatic, expressive | Creative content |

### 3.5 Client Events (iOS → Server → OpenAI)

| Event Type | Purpose |
|------------|---------|
| `session.update` | Update session configuration |
| `input_audio_buffer.append` | Send audio chunks (base64 PCM16) |
| `input_audio_buffer.commit` | Commit audio for processing |
| `input_audio_buffer.clear` | Clear pending audio |
| `response.create` | Trigger AI response |
| `response.cancel` | Cancel ongoing response |
| `conversation.item.create` | Add text/audio items |
| `conversation.item.truncate` | Truncate assistant audio |

### 3.6 Server Events (OpenAI → Server → iOS)

| Event Type | Purpose |
|------------|---------|
| `session.created` | Session initialized |
| `session.updated` | Configuration confirmed |
| `input_audio_buffer.speech_started` | User started speaking |
| `input_audio_buffer.speech_stopped` | User stopped speaking |
| `conversation.item.input_audio_transcription.completed` | User transcript ready |
| `response.created` | AI response started |
| `response.output_audio.delta` | Audio chunk (stream) |
| `response.output_audio.done` | Audio complete |
| `response.output_audio_transcript.delta` | AI transcript chunk |
| `response.done` | Response complete |
| `error` | Error occurred |

---

## 4. Twilio Integration Specification

### 4.1 Voice SDK Setup (iOS)

```swift
// Package Dependency
.package(url: "https://github.com/twilio/twilio-voice-ios", from: "6.13.0")

// Required Capabilities
- Push Notifications
- Background Modes: Voice over IP, Audio
- Microphone Usage Description
```

### 4.2 Access Token Generation (Server)

```javascript
const AccessToken = require('twilio').jwt.AccessToken;
const VoiceGrant = AccessToken.VoiceGrant;

function generateAccessToken(identity) {
  const token = new AccessToken(
    TWILIO_ACCOUNT_SID,
    TWILIO_API_KEY,
    TWILIO_API_SECRET,
    { identity }
  );
  
  const voiceGrant = new VoiceGrant({
    outgoingApplicationSid: TWIML_APP_SID,
    incomingAllow: true
  });
  
  token.addGrant(voiceGrant);
  return token.toJwt();
}
```

### 4.3 TwiML Application Webhooks

```xml
<!-- Outgoing Call TwiML -->
<Response>
  <Connect>
    <Stream url="wss://your-server.railway.app/media-stream">
      <Parameter name="callSid" value="{{CallSid}}" />
      <Parameter name="direction" value="outbound" />
    </Stream>
  </Connect>
</Response>

<!-- Incoming Call TwiML -->
<Response>
  <Say>Please hold while we connect you.</Say>
  <Connect>
    <Stream url="wss://your-server.railway.app/media-stream">
      <Parameter name="callSid" value="{{CallSid}}" />
      <Parameter name="direction" value="inbound" />
      <Parameter name="from" value="{{From}}" />
    </Stream>
  </Connect>
</Response>
```

### 4.4 Media Stream WebSocket Protocol

```typescript
// Twilio → Server (Incoming Audio)
interface TwilioMediaMessage {
  event: "media";
  streamSid: string;
  media: {
    track: "inbound";
    chunk: string;     // base64 μ-law audio
    timestamp: string;
  };
}

// Server → Twilio (Outgoing Audio)
interface TwilioMediaOut {
  event: "media";
  streamSid: string;
  media: {
    payload: string;   // base64 μ-law audio
  };
}
```

---

## 5. WebSocket Bridge Server Specification

### 5.1 Server Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Bridge Server (Node.js)                  │
│                                                             │
│  ┌─────────────┐      ┌─────────────┐      ┌─────────────┐ │
│  │   Twilio    │      │   Audio     │      │   OpenAI    │ │
│  │   Media     │ ───► │   Processor │ ───► │   Realtime  │ │
│  │   Handler   │      │             │      │   Handler   │ │
│  │             │ ◄─── │  μ-law↔PCM  │ ◄─── │             │ │
│  └─────────────┘      └─────────────┘      └─────────────┘ │
│         ▲                                         │        │
│         │                                         ▼        │
│  ┌─────────────┐                          ┌─────────────┐  │
│  │   Express   │                          │  PostgreSQL │  │
│  │   REST API  │                          │  (Railway)  │  │
│  └─────────────┘                          └─────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 Audio Format Conversion

```javascript
// Twilio: μ-law 8kHz mono → OpenAI: PCM16 24kHz mono
function mulawToPCM16_24k(mulawBuffer) {
  // 1. Decode μ-law to PCM16 @ 8kHz
  const pcm8k = decodeMulaw(mulawBuffer);
  
  // 2. Resample 8kHz → 24kHz (3x interpolation)
  const pcm24k = resample(pcm8k, 8000, 24000);
  
  return pcm24k;
}

// OpenAI: PCM16 24kHz mono → Twilio: μ-law 8kHz mono
function pcm16_24kToMulaw(pcm24kBuffer) {
  // 1. Resample 24kHz → 8kHz
  const pcm8k = resample(pcm24kBuffer, 24000, 8000);
  
  // 2. Encode PCM16 to μ-law
  const mulaw = encodeMulaw(pcm8k);
  
  return mulaw;
}
```

### 5.3 WebSocket Endpoints

| Endpoint | Purpose | Protocol |
|----------|---------|----------|
| `wss://server/media-stream` | Twilio Media Streams | Twilio Media Protocol |
| `wss://server/ios-client` | iOS App Connection | Custom JSON Protocol |
| `wss://server/events` | Event Streaming (iOS) | Server-Sent Events over WS |

### 5.4 REST API Endpoints

| Method | Endpoint | Purpose |
|--------|----------|---------|
| `POST` | `/api/token` | Generate Twilio access token |
| `POST` | `/api/calls/outgoing` | Initiate outgoing call |
| `POST` | `/api/calls/:id/end` | End active call |
| `GET` | `/api/calls/history` | Get call history |
| `GET` | `/api/recordings` | List recordings |
| `GET` | `/api/recordings/:id` | Get recording audio |
| `POST` | `/api/prompts` | Save prompt template |
| `GET` | `/api/prompts` | List saved prompts |
| `GET` | `/api/events/:callId` | Get call events log |
| `POST` | `/api/session/config` | Update OpenAI session config |

---

## 6. iOS Application Specification

### 6.1 Project Structure

```
VoiceAIPro/
├── App/
│   ├── VoiceAIProApp.swift
│   └── AppDelegate.swift
├── Core/
│   ├── Services/
│   │   ├── TwilioVoiceService.swift
│   │   ├── WebSocketService.swift
│   │   ├── AudioSessionManager.swift
│   │   └── CallKitManager.swift
│   ├── Models/
│   │   ├── CallSession.swift
│   │   ├── RealtimeConfig.swift
│   │   ├── CallEvent.swift
│   │   └── Prompt.swift
│   └── Managers/
│       ├── CallManager.swift
│       └── RecordingManager.swift
├── Features/
│   ├── Dashboard/
│   │   ├── DashboardView.swift
│   │   └── DashboardViewModel.swift
│   ├── Dialer/
│   │   ├── DialerView.swift
│   │   └── DialerViewModel.swift
│   ├── ActiveCall/
│   │   ├── ActiveCallView.swift
│   │   └── ActiveCallViewModel.swift
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   ├── VADConfigView.swift
│   │   ├── VoiceSelectionView.swift
│   │   └── NoiseReductionView.swift
│   ├── EventLog/
│   │   ├── EventLogView.swift
│   │   └── EventLogViewModel.swift
│   ├── CallHistory/
│   │   ├── CallHistoryView.swift
│   │   └── CallHistoryViewModel.swift
│   ├── Recordings/
│   │   ├── RecordingsView.swift
│   │   └── RecordingsViewModel.swift
│   └── Prompts/
│       ├── PromptsView.swift
│       ├── PromptEditorView.swift
│       └── PromptsViewModel.swift
├── Data/
│   ├── SwiftData/
│   │   ├── CallRecord.swift
│   │   ├── SavedPrompt.swift
│   │   └── EventLogEntry.swift
│   └── Networking/
│       ├── APIClient.swift
│       └── WebSocketClient.swift
├── Utilities/
│   ├── AudioConverter.swift
│   ├── Extensions/
│   └── Constants.swift
└── Resources/
    ├── Assets.xcassets
    └── Info.plist
```

### 6.2 SwiftUI View Hierarchy

```
TabView
├── Tab 1: Dashboard
│   ├── QuickDialView
│   ├── ActiveCallCard (conditional)
│   └── RecentCallsList
├── Tab 2: Dialer
│   ├── PhoneNumberInput
│   ├── PromptSelector
│   └── CallButton
├── Tab 3: History
│   ├── CallHistoryList
│   └── CallDetailView (navigation)
├── Tab 4: Recordings
│   ├── RecordingsList
│   └── AudioPlayerView (sheet)
├── Tab 5: Settings
│   ├── AI Configuration
│   │   ├── Voice Selection
│   │   ├── VAD Configuration
│   │   ├── Noise Reduction
│   │   └── Temperature/Tokens
│   ├── Prompts Management
│   └── Account Settings
└── Overlay: EventLogSheet (debug)
```

### 6.3 Configuration Data Models

```swift
// RealtimeConfig.swift
struct RealtimeConfig: Codable {
    var model: RealtimeModel = .gptRealtime
    var voice: RealtimeVoice = .marin
    var voiceSpeed: Double = 1.0
    var vadConfig: VADConfig = .serverVAD()
    var noiseReduction: NoiseReduction? = nil
    var transcriptionModel: TranscriptionModel = .whisper1
    var temperature: Double = 0.8
    var maxOutputTokens: Int = 4096
    var instructions: String = ""
}

enum RealtimeModel: String, Codable, CaseIterable {
    case gptRealtime = "gpt-realtime"
    case gptRealtimeMini = "gpt-realtime-mini"
}

enum RealtimeVoice: String, Codable, CaseIterable {
    case marin, cedar, alloy, echo, shimmer
    case ash, ballad, coral, sage, verse
}

enum VADConfig: Codable {
    case serverVAD(ServerVADParams)
    case semanticVAD(SemanticVADParams)
    case disabled
    
    static func serverVAD(
        threshold: Double = 0.5,
        prefixPadding: Int = 300,
        silenceDuration: Int = 500,
        idleTimeout: Int? = nil,
        createResponse: Bool = true,
        interruptResponse: Bool = true
    ) -> VADConfig {
        .serverVAD(ServerVADParams(
            threshold: threshold,
            prefixPaddingMs: prefixPadding,
            silenceDurationMs: silenceDuration,
            idleTimeoutMs: idleTimeout,
            createResponse: createResponse,
            interruptResponse: interruptResponse
        ))
    }
}

struct ServerVADParams: Codable {
    var threshold: Double
    var prefixPaddingMs: Int
    var silenceDurationMs: Int
    var idleTimeoutMs: Int?
    var createResponse: Bool
    var interruptResponse: Bool
}

struct SemanticVADParams: Codable {
    var eagerness: Eagerness
    var createResponse: Bool
    var interruptResponse: Bool
    
    enum Eagerness: String, Codable, CaseIterable {
        case low, medium, high, auto
    }
}

enum NoiseReduction: String, Codable, CaseIterable {
    case nearField = "near_field"
    case farField = "far_field"
}

enum TranscriptionModel: String, Codable, CaseIterable {
    case whisper1 = "whisper-1"
    case gpt4oTranscribe = "gpt-4o-transcribe"
}
```

### 6.4 Call Event Model

```swift
struct CallEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let callId: String
    let eventType: EventType
    let direction: EventDirection
    let payload: String?
    
    enum EventType: String, Codable {
        // Session Events
        case sessionCreated = "session.created"
        case sessionUpdated = "session.updated"
        
        // Audio Events
        case speechStarted = "input_audio_buffer.speech_started"
        case speechStopped = "input_audio_buffer.speech_stopped"
        case audioBufferCommitted = "input_audio_buffer.committed"
        
        // Transcription Events
        case inputTranscriptionCompleted = "conversation.item.input_audio_transcription.completed"
        case outputTranscriptDelta = "response.output_audio_transcript.delta"
        
        // Response Events
        case responseCreated = "response.created"
        case responseAudioDelta = "response.output_audio.delta"
        case responseAudioDone = "response.output_audio.done"
        case responseDone = "response.done"
        
        // Error Events
        case error = "error"
        
        // Custom/Bridge Events
        case callConnected = "call.connected"
        case callDisconnected = "call.disconnected"
        case configUpdated = "config.updated"
    }
    
    enum EventDirection: String, Codable {
        case incoming  // Server → Client
        case outgoing  // Client → Server
    }
}
```

---

## 7. Database Schema (Railway PostgreSQL)

### 7.1 Tables

```sql
-- Users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_active TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Call sessions
CREATE TABLE call_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    call_sid VARCHAR(255) UNIQUE,
    direction VARCHAR(20) NOT NULL, -- 'inbound' | 'outbound'
    phone_number VARCHAR(50),
    status VARCHAR(50) NOT NULL,
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ended_at TIMESTAMP,
    duration_seconds INTEGER,
    prompt_id UUID REFERENCES prompts(id),
    config_snapshot JSONB
);

-- Call events log
CREATE TABLE call_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    call_session_id UUID REFERENCES call_sessions(id) ON DELETE CASCADE,
    event_type VARCHAR(100) NOT NULL,
    direction VARCHAR(20) NOT NULL, -- 'incoming' | 'outgoing'
    payload JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Recordings
CREATE TABLE recordings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    call_session_id UUID REFERENCES call_sessions(id) ON DELETE CASCADE,
    storage_path VARCHAR(500) NOT NULL,
    duration_seconds INTEGER,
    file_size_bytes BIGINT,
    format VARCHAR(20) DEFAULT 'wav',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Transcripts
CREATE TABLE transcripts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    call_session_id UUID REFERENCES call_sessions(id) ON DELETE CASCADE,
    speaker VARCHAR(20) NOT NULL, -- 'user' | 'assistant'
    content TEXT NOT NULL,
    timestamp_ms INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Saved prompts
CREATE TABLE prompts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    name VARCHAR(255) NOT NULL,
    instructions TEXT NOT NULL,
    voice VARCHAR(50) DEFAULT 'marin',
    vad_config JSONB,
    is_default BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes
CREATE INDEX idx_call_sessions_user ON call_sessions(user_id);
CREATE INDEX idx_call_events_session ON call_events(call_session_id);
CREATE INDEX idx_call_events_type ON call_events(event_type);
CREATE INDEX idx_recordings_session ON recordings(call_session_id);
CREATE INDEX idx_transcripts_session ON transcripts(call_session_id);
CREATE INDEX idx_prompts_user ON prompts(user_id);
```

---

## 8. User Interface Specifications

### 8.1 Design System

**Color Palette:**
```swift
extension Color {
    static let voiceAIPrimary = Color(hex: "007AFF")      // iOS Blue
    static let voiceAISecondary = Color(hex: "5856D6")   // Purple
    static let voiceAISuccess = Color(hex: "34C759")     // Green
    static let voiceAIWarning = Color(hex: "FF9500")     // Orange
    static let voiceAIError = Color(hex: "FF3B30")       // Red
    static let voiceAIBackground = Color(.systemBackground)
    static let voiceAISurface = Color(.secondarySystemBackground)
}
```

**Typography (SF Pro):**
- Large Title: 34pt Bold
- Title 1: 28pt Bold
- Title 2: 22pt Bold
- Headline: 17pt Semibold
- Body: 17pt Regular
- Callout: 16pt Regular
- Caption: 12pt Regular

### 8.2 Key Screens

#### Dashboard
- Active call indicator with waveform visualization
- Quick dial pad
- Recent calls (last 5)
- System status indicators

#### Settings → AI Configuration
- **Voice Selection:** Grid of voice options with audio preview
- **VAD Configuration:**
  - Toggle between Server VAD / Semantic VAD / Disabled
  - Server VAD sliders: threshold, prefix padding, silence duration
  - Semantic VAD: eagerness picker (low/medium/high/auto)
  - Toggles: create_response, interrupt_response
- **Noise Reduction:** near_field / far_field / off
- **Model:** gpt-realtime / gpt-realtime-mini
- **Temperature:** Slider 0.6 - 1.2
- **Max Tokens:** Stepper or slider

#### Event Log
- Real-time scrolling list of events
- Color-coded by event type
- Expandable JSON payload viewer
- Filter by event type
- Export functionality

#### Recordings
- List with duration, date, phone number
- Inline audio player with waveform
- Transcript view (side-by-side)
- Share/export options

---

## 9. Security Considerations

### 9.1 Authentication & Authorization
- Device-based authentication with secure enclave storage
- Twilio access tokens: short-lived (1 hour max)
- OpenAI API key: server-side only, never exposed to client
- HTTPS/WSS for all communications

### 9.2 Data Protection
- Call recordings encrypted at rest (AES-256)
- PII masking in logs
- GDPR-compliant data retention policies
- Option to disable recording per call

### 9.3 API Security
- Rate limiting on all endpoints
- Input validation and sanitization
- CORS configuration for WebSocket origins

---

## 10. Performance Requirements

| Metric | Target |
|--------|--------|
| Call connection time | < 3 seconds |
| Audio latency (round-trip) | < 500ms |
| Time to first AI response | < 800ms |
| Event log update frequency | Real-time (< 100ms) |
| Recording start delay | < 1 second |
| App launch to ready | < 2 seconds |

---

## 11. Technology Stack Summary

### iOS Application
- **Language:** Swift 5.9+
- **UI Framework:** SwiftUI with UIKit integration
- **Minimum iOS:** 17.0
- **Architecture:** MVVM with Coordinators
- **Dependencies:**
  - TwilioVoice (~> 6.13)
  - SwiftData (native)
  - Combine (native)

### WebSocket Bridge Server
- **Runtime:** Node.js 20 LTS
- **Framework:** Express.js 4.x
- **WebSocket:** ws 8.x
- **Database:** PostgreSQL 15 (Railway)
- **Audio Processing:** Custom μ-law/PCM conversion
- **Key Dependencies:**
  - twilio (^4.x)
  - ws (^8.x)
  - pg (^8.x)
  - dotenv

### Infrastructure
- **Server Hosting:** Railway (WebSocket-compatible)
- **Database:** Railway PostgreSQL
- **Recording Storage:** Railway Volume or S3-compatible
- **Monitoring:** Railway metrics + custom logging

---

## 12. Deployment Checklist

### Pre-Deployment
- [ ] Twilio account with Voice capability
- [ ] OpenAI API key with Realtime access
- [ ] Apple Developer account
- [ ] VoIP push certificate generated
- [ ] Railway project created

### Server Deployment
- [ ] Environment variables configured
- [ ] PostgreSQL database provisioned
- [ ] WebSocket endpoint accessible
- [ ] TwiML webhook URLs configured
- [ ] Health check endpoint responding

### iOS Deployment
- [ ] Push notification entitlements
- [ ] Background modes configured
- [ ] Microphone usage description
- [ ] CallKit integration tested
- [ ] TestFlight beta deployed

---

## Appendix A: Environment Variables

```bash
# Server Environment
NODE_ENV=production
PORT=3000

# Twilio
TWILIO_ACCOUNT_SID=ACxxxxx
TWILIO_AUTH_TOKEN=xxxxx
TWILIO_API_KEY=SKxxxxx
TWILIO_API_SECRET=xxxxx
TWIML_APP_SID=APxxxxx
TWILIO_PHONE_NUMBER=+1xxxxxxxxxx

# OpenAI
OPENAI_API_KEY=sk-xxxxx

# Database
DATABASE_URL=postgresql://user:pass@host:5432/db

# Recording Storage
RECORDING_STORAGE_PATH=/data/recordings
# Or for S3:
# AWS_ACCESS_KEY_ID=xxxxx
# AWS_SECRET_ACCESS_KEY=xxxxx
# S3_BUCKET_NAME=voiceai-recordings
```

---

## Appendix B: API Error Codes

| Code | Description | Resolution |
|------|-------------|------------|
| `E001` | Invalid Twilio token | Refresh token |
| `E002` | OpenAI connection failed | Check API key |
| `E003` | Audio format error | Check encoding |
| `E004` | Session expired | Reconnect |
| `E005` | Rate limit exceeded | Back off |
| `E006` | Invalid phone number | Validate format |
| `E007` | Recording failed | Check storage |
| `E008` | Database error | Check connection |

---

*End of Technical Specification*
