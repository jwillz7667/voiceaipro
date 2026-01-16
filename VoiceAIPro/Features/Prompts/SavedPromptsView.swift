import SwiftUI

/// View for browsing and selecting saved prompts/instructions
struct SavedPromptsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DIContainer
    @Environment(\.dismiss) private var dismiss

    @State private var prompts: [PromptDTO] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var showCreateSheet = false
    @State private var promptToEdit: PromptDTO?
    @State private var promptToDelete: PromptDTO?
    @State private var showDeleteAlert = false

    private var filteredPrompts: [PromptDTO] {
        if searchText.isEmpty {
            return prompts
        }
        return prompts.filter { prompt in
            prompt.name.localizedCaseInsensitiveContains(searchText) ||
            prompt.instructions.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && prompts.isEmpty {
                    ProgressView("Loading prompts...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage, prompts.isEmpty {
                    errorView(message: error)
                } else if prompts.isEmpty {
                    emptyState
                } else {
                    promptsList
                }
            }
            .navigationTitle("Saved Instructions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search prompts")
            .refreshable {
                await fetchPrompts()
            }
            .task {
                await fetchPrompts()
            }
            .sheet(isPresented: $showCreateSheet) {
                PromptEditorSheet(mode: .create) { newPrompt in
                    prompts.insert(newPrompt, at: 0)
                }
            }
            .sheet(item: $promptToEdit) { prompt in
                PromptEditorSheet(mode: .edit(prompt)) { updatedPrompt in
                    if let index = prompts.firstIndex(where: { $0.id == updatedPrompt.id }) {
                        prompts[index] = updatedPrompt
                    }
                }
            }
            .alert("Delete Prompt", isPresented: $showDeleteAlert, presenting: promptToDelete) { prompt in
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        await deletePrompt(prompt)
                    }
                }
            } message: { prompt in
                Text("Are you sure you want to delete \"\(prompt.name)\"? This action cannot be undone.")
            }
        }
    }

    private var promptsList: some View {
        List {
            ForEach(filteredPrompts) { prompt in
                PromptRow(
                    prompt: prompt,
                    isSelected: appState.selectedPrompt?.id == prompt.id,
                    onSelect: {
                        selectPrompt(prompt)
                    },
                    onEdit: {
                        promptToEdit = prompt
                    }
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        promptToDelete = prompt
                        showDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Button {
                        promptToEdit = prompt
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Saved Prompts", systemImage: "doc.text")
        } description: {
            Text("Create your first prompt to customize how the AI responds during calls.")
        } actions: {
            Button("Create Prompt") {
                showCreateSheet = true
            }
            .buttonStyle(.bordered)
        }
    }

    private func errorView(message: String) -> some View {
        ContentUnavailableView {
            Label("Error Loading Prompts", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                Task { await fetchPrompts() }
            }
            .buttonStyle(.bordered)
        }
    }

    private func fetchPrompts() async {
        isLoading = true
        errorMessage = nil

        do {
            let fetchedPrompts = try await container.apiClient.getPromptsTyped()
            await MainActor.run {
                prompts = fetchedPrompts
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load prompts: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    private func selectPrompt(_ prompt: PromptDTO) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Convert PromptDTO to Prompt and set as selected
        let selectedPrompt = prompt.toPrompt()
        appState.selectedPrompt = selectedPrompt

        // Also update the realtime config with this prompt's settings
        appState.realtimeConfig.instructions = prompt.instructions
        if let voice = prompt.voice, let voiceEnum = RealtimeVoice(rawValue: voice) {
            appState.realtimeConfig.voice = voiceEnum
        }

        dismiss()
    }

    private func deletePrompt(_ prompt: PromptDTO) async {
        do {
            try await container.apiClient.deletePrompt(id: prompt.id)
            await MainActor.run {
                prompts.removeAll { $0.id == prompt.id }

                // If we deleted the selected prompt, clear selection
                if appState.selectedPrompt?.id == prompt.id {
                    appState.selectedPrompt = nil
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to delete prompt: \(error.localizedDescription)"
            }
        }
    }
}

/// Row displaying a single prompt
struct PromptRow: View {
    let prompt: PromptDTO
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 16, height: 16)
                    }
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(prompt.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)

                        if prompt.isDefault {
                            Text("Default")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .clipShape(Capsule())
                        }

                        Spacer()

                        if let voice = prompt.voice {
                            Text(voice.capitalized)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }

                        Button {
                            onEdit()
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.blue.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }

                    Text(prompt.instructions)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SavedPromptsView()
        .environmentObject(AppState())
        .environmentObject(DIContainer.shared)
}
