import SwiftUI

/// Card on home screen for selecting AI prompt/instructions before making a call
struct PromptSelectorCard: View {
    @EnvironmentObject var appState: AppState
    @State private var showPromptsList = false

    var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            showPromptsList = true
        } label: {
            GlassCard(padding: 12) {
                HStack(spacing: 12) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 40, height: 40)

                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.blue)
                    }

                    // Content
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI Instructions")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)

                        if let prompt = appState.selectedPrompt {
                            Text(prompt.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        } else {
                            Text("Using Default")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                        }

                        // Instructions preview
                        Text(instructionsPreview)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPromptsList) {
            SavedPromptsView()
        }
    }

    private var instructionsPreview: String {
        let instructions = appState.selectedPrompt?.instructions ?? appState.realtimeConfig.instructions

        if instructions.isEmpty {
            return "Tap to select instructions"
        }

        // Truncate for preview
        let maxLength = 50
        if instructions.count > maxLength {
            return String(instructions.prefix(maxLength)) + "..."
        }
        return instructions
    }
}

/// Compact version of the prompt selector for smaller spaces
struct CompactPromptSelector: View {
    @EnvironmentObject var appState: AppState
    @State private var showPromptsList = false

    var body: some View {
        Button {
            showPromptsList = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 12))

                Text(appState.selectedPrompt?.name ?? "Default")
                    .font(.system(size: 13, weight: .medium))

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.1))
            .clipShape(Capsule())
        }
        .sheet(isPresented: $showPromptsList) {
            SavedPromptsView()
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        PromptSelectorCard()
        CompactPromptSelector()
    }
    .padding()
    .environmentObject(AppState())
}
