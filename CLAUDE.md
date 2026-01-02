# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

VoiceAI Pro is a bidirectional AI voice calling system consisting of:
1. **iOS App** - SwiftUI app with Twilio Voice SDK for making/receiving calls
2. **Bridge Server** - Node.js WebSocket server connecting Twilio Media Streams to OpenAI Realtime API

The system enables AI-powered phone conversations where an AI agent handles both incoming and outgoing PSTN calls.

## Build & Run Commands

### iOS App
```bash
# Build
xcodebuild -project real.xcodeproj -scheme real -configuration Debug -destination 'generic/platform=iOS' build

# Run tests
xcodebuild -project real.xcodeproj -scheme realTests test -destination 'platform=iOS Simulator,name=iPhone 16'

# Or use Xcode: ⌘B to build, ⌘R to run
```

### Server
```bash
cd server

# Install dependencies
npm install

# Run development server (with hot reload)
npm run dev

# Run production
npm start

# Run database migrations
npm run migrate

# Lint
npm run lint
```

## Architecture

### System Flow
```
iOS App ←→ Twilio Voice SDK ←→ Twilio Cloud (PSTN)
                                    ↓
                            Bridge Server (Node.js)
                              ↓           ↓
                    Twilio Media    OpenAI Realtime
                    Streams         API (gpt-realtime)
                    (μ-law 8kHz)    (PCM16 24kHz)
```

### iOS App Structure (`VoiceAIPro/`)
- **App/** - VoiceAIProApp.swift (entry point), AppDelegate.swift (PushKit/VoIP)
- **Core/Managers/** - AppState (global state), CallManager (orchestrator)
- **Core/Services/** - TwilioVoiceService, CallKitManager, AudioSessionManager
- **Core/Models/** - CallSession, RealtimeConfig, CallEvent, Prompt
- **Data/SwiftData/** - CallRecord, SavedPrompt, EventLogEntry, UserSettings
- **Utilities/Constants.swift** - API URLs, toggle `useLocalServer` for dev/prod

### Server Structure (`server/src/`)
- **index.js** - Express app, WebSocket server setup, health endpoints
- **websocket/** - Connection handlers:
  - `twilioMediaHandler.js` - Twilio Media Stream processing
  - `openaiRealtimeHandler.js` - OpenAI Realtime API client, **default instructions here**
  - `connectionManager.js` - Session management, **default VAD config here**
  - `iosClientHandler.js` - iOS app WebSocket connections
- **routes/** - REST endpoints (token, twiml, calls, prompts, recordings)
- **db/** - PostgreSQL queries and migrations
- **audio/** - μ-law ↔ PCM16 conversion

## Key Configuration Points

### AI Instructions & Voice
Edit `server/src/websocket/openaiRealtimeHandler.js`:
```javascript
function getDefaultInstructions() {
  return `Your custom AI instructions here...`;
}
```

### VAD (Voice Activity Detection)
Edit `server/src/websocket/connectionManager.js`:
```javascript
vadType: 'semantic_vad',  // or 'server_vad'
vadConfig: {
  eagerness: 'high',      // 'low', 'medium', 'high', 'auto'
}
```

### Server URL (iOS)
Edit `VoiceAIPro/Utilities/Constants.swift`:
```swift
static let useLocalServer = false  // true for localhost:3000
static let productionURL = "https://your-server.railway.app"
```

## Environment Variables (server/.env)

Required:
- `DATABASE_URL` - PostgreSQL connection string
- `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_PHONE_NUMBER`
- `OPENAI_API_KEY`

Optional (for iOS SDK tokens):
- `TWILIO_API_KEY`, `TWILIO_API_SECRET`, `TWIML_APP_SID`

## API Endpoints

- `GET /health` - Simple health check (for Railway)
- `GET /status` - Detailed status with DB and Twilio info
- `POST /api/token` - Generate Twilio access token (requires API Key/Secret)
- `POST /twiml/incoming` - TwiML webhook for incoming calls
- `POST /twiml/outgoing` - TwiML webhook for outgoing calls
- `GET /api/prompts` - List saved prompts
- `GET /api/calls/history` - Call history

WebSocket:
- `/media-stream` - Twilio Media Stream connection
- `/ios-client` - iOS app real-time events
- `/events/:callId` - Call event streaming

## Tech Stack

**iOS:** Swift 5, SwiftUI, SwiftData, CallKit, PushKit, TwilioVoice SDK
**Server:** Node.js 20+, Express, ws, pg (PostgreSQL), Twilio SDK
**Deployment:** Railway (server), App Store (iOS)
