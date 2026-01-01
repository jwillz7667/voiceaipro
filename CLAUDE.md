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
- **Minimum iOS:** 26.1
- **Concurrency:** Swift Approachable Concurrency with MainActor default isolation

## Architecture

This is a SwiftUI app using SwiftData for persistence:

- **realApp.swift** - App entry point, configures `ModelContainer` with schema
- **ContentView.swift** - Main view with NavigationSplitView pattern
- **Item.swift** - SwiftData `@Model` class for data persistence

The app follows MVVM architecture as it evolves toward the full VoiceAI Pro implementation.

## Planned Architecture (per VoiceAI_Technical_Specification.md)

The full implementation will include:
- **Core/Services/** - TwilioVoiceService, WebSocketService, AudioSessionManager, CallKitManager
- **Core/Models/** - CallSession, RealtimeConfig, CallEvent, Prompt
- **Features/** - Dashboard, Dialer, ActiveCall, Settings, EventLog, CallHistory, Recordings, Prompts
- **Data/** - SwiftData models, APIClient, WebSocketClient

## Key Dependencies (to be added)

- TwilioVoice (~> 6.13) - VoIP signaling and audio
- SwiftData (native) - Local persistence
- Combine (native) - Reactive programming

## Testing

Uses Swift Testing framework (`import Testing`) with `@Test` attributes for unit tests.
