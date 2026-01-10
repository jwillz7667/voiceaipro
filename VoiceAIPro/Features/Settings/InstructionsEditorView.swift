import SwiftUI

/// System instructions editor with AI optimization
struct InstructionsEditorView: View {
    @EnvironmentObject var container: DIContainer
    @Binding var instructions: String
    @Environment(\.dismiss) private var dismiss

    @State private var editedInstructions: String = ""
    @State private var showingTemplates = false
    @State private var isOptimizing = false
    @State private var optimizeError: String?

    private let characterLimit = 10000

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Optimize toolbar at top of text box
                HStack {
                    Text("Instructions")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)

                    Spacer()

                    if isOptimizing {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Optimizing...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.purple)
                        }
                    } else {
                        Button(action: optimizeInstructions) {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Optimize")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(canOptimize ? .purple : .gray)
                        }
                        .disabled(!canOptimize)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemBackground))

                // Error banner
                if let error = optimizeError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 14))
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            optimizeError = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                }

                // Editor
                ZStack(alignment: .topLeading) {
                    if editedInstructions.isEmpty {
                        Text("Enter system instructions for the AI...")
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }

                    TextEditor(text: $editedInstructions)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .scrollContentBackground(.hidden)
                        .background(Color(.systemBackground))
                        .disabled(isOptimizing)
                        .opacity(isOptimizing ? 0.6 : 1)
                }
                .frame(maxHeight: .infinity)

                Divider()

                // Footer with character count and templates
                HStack {
                    Button(action: {
                        showingTemplates = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                            Text("Templates")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blue)
                    }
                    .disabled(isOptimizing)

                    Spacer()

                    Text("\(editedInstructions.count) / \(characterLimit)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(
                            editedInstructions.count > characterLimit ? .red : .secondary
                        )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground))
            }
            .navigationTitle("Instructions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isOptimizing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        instructions = editedInstructions
                        dismiss()
                    }
                    .disabled(editedInstructions.count > characterLimit || isOptimizing)
                }
            }
            .onAppear {
                editedInstructions = instructions
            }
            .sheet(isPresented: $showingTemplates) {
                InstructionTemplatesSheet { template in
                    editedInstructions = template.content
                }
            }
        }
    }

    private var canOptimize: Bool {
        let trimmed = editedInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 10 && !isOptimizing
    }

    private func optimizeInstructions() {
        guard canOptimize else { return }

        isOptimizing = true
        optimizeError = nil

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        Task {
            do {
                let optimized = try await container.apiClient.optimizePrompt(
                    instructions: editedInstructions
                )

                await MainActor.run {
                    editedInstructions = optimized
                    isOptimizing = false

                    let successGenerator = UINotificationFeedbackGenerator()
                    successGenerator.notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    isOptimizing = false
                    optimizeError = error.localizedDescription

                    let errorGenerator = UINotificationFeedbackGenerator()
                    errorGenerator.notificationOccurred(.error)
                }
            }
        }
    }
}

/// Instruction templates sheet
struct InstructionTemplatesSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSelect: (InstructionTemplate) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(InstructionTemplate.allTemplates) { template in
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        onSelect(template)
                        dismiss()
                    }) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: template.icon)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(template.color)
                                    .frame(width: 28)

                                Text(template.name)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.primary)

                                Spacer()
                            }

                            Text(template.preview)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Instruction template model
struct InstructionTemplate: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let color: Color
    let content: String

    var preview: String {
        String(content.prefix(150)) + (content.count > 150 ? "..." : "")
    }

    static let allTemplates: [InstructionTemplate] = [
        InstructionTemplate(
            name: "Professional Assistant",
            icon: "briefcase.fill",
            color: .blue,
            content: """
            You are a professional AI assistant. Be helpful, accurate, and concise.

            Key behaviors:
            - Provide clear, actionable information
            - Ask clarifying questions when needed
            - Maintain a professional but friendly tone
            - Respect the caller's time
            """
        ),
        InstructionTemplate(
            name: "Customer Support",
            icon: "headphones",
            color: .green,
            content: """
            You are a friendly customer support representative. Your goal is to help customers resolve their issues efficiently while maintaining a positive experience.

            Guidelines:
            - Listen actively and acknowledge concerns
            - Provide step-by-step solutions
            - Offer alternatives when the first solution doesn't work
            - Escalate complex issues appropriately
            - End calls with a summary of actions taken
            """
        ),
        InstructionTemplate(
            name: "Sales Representative",
            icon: "chart.line.uptrend.xyaxis",
            color: .orange,
            content: """
            You are an engaging sales representative. Your goal is to understand customer needs and present relevant solutions.

            Approach:
            - Build rapport quickly
            - Ask discovery questions to understand needs
            - Present benefits, not just features
            - Handle objections with empathy
            - Guide toward a decision without pressure
            """
        ),
        InstructionTemplate(
            name: "Appointment Scheduler",
            icon: "calendar.badge.clock",
            color: .purple,
            content: """
            You are an efficient appointment scheduling assistant. Help callers find and book suitable appointment times.

            Process:
            - Greet the caller and ask for their preferred date/time
            - Check availability and offer alternatives
            - Confirm all appointment details
            - Send confirmation and reminder instructions
            - Handle rescheduling and cancellations
            """
        ),
        InstructionTemplate(
            name: "Character: Li Mei Chen",
            icon: "theatermasks.fill",
            color: .red,
            content: """
            You are Li Mei Chen, a 58-year-old Chinese mother who just got a TERRIBLE haircut that ruined her life. You are calling your daughter to complain dramatically.

            Your personality:
            - Extremely dramatic about the haircut
            - Mix English with occasional Mandarin expressions
            - Compare everything to how things were done "back in China"
            - Guilt-trip your daughter subtly
            - Eventually calm down but never fully accept the haircut

            Start the conversation by wailing about your ruined hair.
            """
        ),
        InstructionTemplate(
            name: "Technical Support",
            icon: "wrench.and.screwdriver.fill",
            color: .teal,
            content: """
            You are a patient and knowledgeable technical support specialist. Help users troubleshoot and resolve technical issues.

            Approach:
            - Gather information about the issue systematically
            - Use simple, non-technical language
            - Guide through troubleshooting steps one at a time
            - Verify each step is completed before moving on
            - Document the solution for future reference
            """
        )
    ]
}

/// Settings row that navigates to instructions editor
struct InstructionsSettingsRow: View {
    @EnvironmentObject var container: DIContainer
    @Binding var instructions: String
    @State private var showingEditor = false

    var body: some View {
        Button(action: {
            showingEditor = true
        }) {
            HStack(spacing: 12) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.blue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("System Instructions")
                        .font(.system(size: 16))
                        .foregroundColor(.primary)

                    if instructions.isEmpty {
                        Text("Using default instructions")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    } else {
                        Text(instructions.prefix(50) + (instructions.count > 50 ? "..." : ""))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showingEditor) {
            InstructionsEditorView(instructions: $instructions)
                .environmentObject(container)
        }
    }
}

#Preview {
    NavigationStack {
        InstructionsEditorView(instructions: .constant("You are a helpful AI assistant."))
            .environmentObject(DIContainer.shared)
    }
}
