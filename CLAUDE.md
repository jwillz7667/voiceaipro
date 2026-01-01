# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

VoiceAI Pro (codenamed "real") is an iOS application for bidirectional AI voice calling. It integrates OpenAI's Realtime API with Twilio's Programmable Voice SDK to enable AI-powered phone conversations.

## Build & Run Commands

```bash
# Build the project
xcodebuild -project real.xcodeproj -scheme real -configuration Debug build

# Run tests
xcodebuild -project real.xcodeproj -scheme realTests test -destination 'platform=iOS Simulator,name=iPhone 16'

# Run UI tests
xcodebuild -project real.xcodeproj -scheme realUITests test -destination 'platform=iOS Simulator,name=iPhone 16'

# Build for release
xcodebuild -project real.xcodeproj -scheme real -configuration Release build
```

Alternatively, open `real.xcodeproj` in Xcode and use ⌘B to build, ⌘R to run.

## Technology Stack

- **Language:** Swift 5.0
- **UI Framework:** SwiftUI
- **Data Persistence:** SwiftData
- **Minimum iOS:** 17.0
- **Concurrency:** Swift Concurrency with MainActor isolation

## Architecture

This is a SwiftUI app using MVVM architecture with SwiftData for persistence:

### App Layer
- **VoiceAIProApp.swift** - Main entry point, configures ModelContainer and services
- **AppDelegate.swift** - System events, PushKit, and VoIP push handling
- **ContentView.swift** - Tab-based UI with all feature screens

### Core Layer
- **Core/Models/** - CallSession, RealtimeConfig, CallEvent, Prompt
- **Core/Services/** - TwilioVoiceService, CallKitManager, AudioSessionManager
- **Core/Managers/** - AppState (global state), CallManager (orchestrator)
- **Core/DI/** - DIContainer (dependency injection)

### Data Layer
- **Data/SwiftData/** - CallRecord, SavedPrompt, EventLogEntry
- **Data/Networking/** - APIClient, WebSocketClient (in DIContainer)

### Utilities
- **Utilities/Constants.swift** - API URLs, Twilio config, audio settings
- **Utilities/Extensions/** - Color, View, Date, String extensions

## Key Dependencies

### Required - Add via Swift Package Manager in Xcode

1. **TwilioVoice** (~> 6.13)
   - URL: `https://github.com/twilio/twilio-voice-ios`
   - Used for: VoIP signaling and audio

To add: Xcode → File → Add Package Dependencies → Enter URL

### Native Frameworks (no import needed)
- SwiftData - Local persistence
- Combine - Reactive programming
- CallKit - Native call UI
- PushKit - VoIP push notifications
- AVFoundation - Audio session management

## Service Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        CallManager                          │
│              (High-level orchestrator)                      │
└─────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ TwilioVoice     │  │ CallKitManager  │  │ AudioSession    │
│ Service         │  │                 │  │ Manager         │
│                 │  │ - CXProvider    │  │                 │
│ - TVOCall       │  │ - CXController  │  │ - AVAudioSession│
│ - TVOCallInvite │  │ - CallKit UI    │  │ - Route mgmt    │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

## VoIP Push Flow

1. Server sends VoIP push via APNs
2. PKPushRegistry receives push in AppDelegate
3. AppDelegate calls CallManager.handleIncomingPush()
4. CallManager → TwilioVoiceService → CallKitManager
5. CallKit displays incoming call UI
6. User answers → Audio session activated → Call connected

## Testing

Uses Swift Testing framework (`import Testing`) with `@Test` attributes for unit tests.

## Important Notes

- VoIP push MUST report to CallKit immediately or iOS terminates the app
- Audio session activation happens in CallKit delegate, not before
- All call cleanup must happen in error paths (defensive programming)
- TwilioVoiceService uses protocol abstractions for SDK types (allows testing without SDK)
