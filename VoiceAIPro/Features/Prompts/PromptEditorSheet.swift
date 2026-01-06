import SwiftUI

/// Mode for the prompt editor
enum PromptEditorMode {
    case create
    case edit(PromptDTO)

    var title: String {
        switch self {
        case .create: return "New Prompt"
        case .edit: return "Edit Prompt"
        }
    }

    var saveButtonTitle: String {
        switch self {
        case .create: return "Create"
        case .edit: return "Save"
        }
    }
}

/// Sheet for creating or editing a prompt
struct PromptEditorSheet: View {
    @EnvironmentObject var container: DIContainer
    @Environment(\.dismiss) private var dismiss

    let mode: PromptEditorMode
    let onSave: (PromptDTO) -> Void

    @State private var name: String = ""
    @State private var instructions: String = ""
    @State private var voice: RealtimeVoice = .marin
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showInstructionsEditor = false

    init(mode: PromptEditorMode, onSave: @escaping (PromptDTO) -> Void) {
        self.mode = mode
        self.onSave = onSave

        // Initialize state based on mode
        if case .edit(let prompt) = mode {
            _name = State(initialValue: prompt.name)
            _instructions = State(initialValue: prompt.instructions)
            if let voiceStr = prompt.voice, let voiceEnum = RealtimeVoice(rawValue: voiceStr) {
                _voice = State(initialValue: voiceEnum)
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // Name Section
                Section {
                    TextField("Prompt Name", text: $name)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Give your prompt a descriptive name")
                }

                // Voice Section
                Section {
                    Picker("Voice", selection: $voice) {
                        ForEach(RealtimeVoice.allCases, id: \.self) { voiceOption in
                            HStack {
                                Circle()
                                    .fill(voiceOption.color)
                                    .frame(width: 12, height: 12)
                                Text(voiceOption.displayName)
                            }
                            .tag(voiceOption)
                        }
                    }
                } header: {
                    Text("Voice")
                }

                // Instructions Section
                Section {
                    Button {
                        showInstructionsEditor = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Instructions")
                                    .foregroundColor(.primary)

                                if instructions.isEmpty {
                                    Text("Tap to add instructions...")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                } else {
                                    Text(instructions)
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("AI Instructions")
                } footer: {
                    Text("Define how the AI should behave during calls. \(instructions.count)/10000 characters")
                }

                // Error Message
                if let error = errorMessage {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .foregroundColor(.secondary)
                                .font(.system(size: 14))
                        }
                    }
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(mode.saveButtonTitle) {
                        Task { await savePrompt() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave || isSaving)
                }
            }
            .sheet(isPresented: $showInstructionsEditor) {
                InstructionsEditorView(instructions: $instructions)
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func savePrompt() async {
        isSaving = true
        errorMessage = nil

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let savedPrompt: PromptDTO

            switch mode {
            case .create:
                savedPrompt = try await container.apiClient.createPrompt(
                    name: trimmedName,
                    instructions: trimmedInstructions,
                    voice: voice.rawValue,
                    vadConfig: nil
                )

            case .edit(let existing):
                savedPrompt = try await container.apiClient.updatePrompt(
                    id: existing.id,
                    name: trimmedName,
                    instructions: trimmedInstructions,
                    voice: voice.rawValue,
                    vadConfig: nil
                )
            }

            await MainActor.run {
                onSave(savedPrompt)
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to save: \(error.localizedDescription)"
                isSaving = false
            }
        }
    }
}


#Preview {
    PromptEditorSheet(mode: .create) { _ in }
        .environmentObject(DIContainer.shared)
}
