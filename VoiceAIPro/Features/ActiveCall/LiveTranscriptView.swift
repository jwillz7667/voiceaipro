import SwiftUI

/// Real-time transcript display during active calls
struct LiveTranscriptView: View {
    @ObservedObject var eventProcessor: EventProcessor
    @State private var isExpanded: Bool = false
    @Namespace private var animation

    var body: some View {
        VStack(spacing: 0) {
            // Header with expand/collapse toggle
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 14, weight: .medium))
                    Text("Live Transcript")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            if isExpanded {
                Divider()
                    .background(Color.white.opacity(0.2))

                // Transcript content
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            // Show current streaming responses
                            if !eventProcessor.currentUserSpeech.isEmpty {
                                TranscriptBubble(
                                    speaker: "You",
                                    text: eventProcessor.currentUserSpeech,
                                    isUser: true,
                                    isStreaming: true
                                )
                            }

                            if !eventProcessor.currentAIResponse.isEmpty {
                                TranscriptBubble(
                                    speaker: "AI",
                                    text: eventProcessor.currentAIResponse,
                                    isUser: false,
                                    isStreaming: true
                                )
                            }

                            // Show completed transcripts
                            if !eventProcessor.userTranscript.isEmpty || !eventProcessor.aiTranscript.isEmpty {
                                TranscriptHistoryView(
                                    userTranscript: eventProcessor.userTranscript,
                                    aiTranscript: eventProcessor.aiTranscript
                                )
                            }

                            // Empty state
                            if eventProcessor.userTranscript.isEmpty &&
                               eventProcessor.aiTranscript.isEmpty &&
                               eventProcessor.currentUserSpeech.isEmpty &&
                               eventProcessor.currentAIResponse.isEmpty {
                                Text("Transcript will appear here...")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.5))
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 20)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding(16)
                    }
                    .frame(maxHeight: 200)
                    .onChange(of: eventProcessor.currentAIResponse) { _, _ in
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: eventProcessor.currentUserSpeech) { _, _ in
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// Individual transcript bubble
struct TranscriptBubble: View {
    let speaker: String
    let text: String
    let isUser: Bool
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            // Speaker label
            HStack(spacing: 4) {
                if !isUser {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                }
                Text(speaker)
                    .font(.system(size: 11, weight: .semibold))
                if isUser {
                    Image(systemName: "person.circle")
                        .font(.system(size: 10))
                }
                if isStreaming {
                    TypingIndicator()
                }
            }
            .foregroundColor(isUser ? .green.opacity(0.8) : .blue.opacity(0.8))

            // Text bubble
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.95))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isUser ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                )
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        }
    }
}

/// Typing indicator animation
struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 4, height: 4)
                    .scaleEffect(animating ? 1 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

/// Display completed transcript history
struct TranscriptHistoryView: View {
    let userTranscript: String
    let aiTranscript: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !userTranscript.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("You said:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.green.opacity(0.7))
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green.opacity(0.5))
                    }
                    Text(userTranscript)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(nil)
                }
            }

            if !aiTranscript.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("AI said:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.blue.opacity(0.7))
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.blue.opacity(0.5))
                    }
                    Text(aiTranscript)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(nil)
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()
            LiveTranscriptView(eventProcessor: {
                let processor = EventProcessor()
                return processor
            }())
            .padding()
        }
    }
}
