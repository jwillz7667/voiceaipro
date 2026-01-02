import SwiftUI
import SwiftData

/// Detailed view of a single call
struct CallDetailView: View {
    let call: CallRecord

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var showingAddFavorite = false

    var body: some View {
        NavigationStack {
            List {
                // Call info header
                Section {
                    VStack(spacing: 16) {
                        // Avatar
                        ZStack {
                            Circle()
                                .fill(statusColor.opacity(0.15))
                                .frame(width: 80, height: 80)

                            Image(systemName: directionIcon)
                                .font(.system(size: 32, weight: .medium))
                                .foregroundColor(statusColor)
                        }

                        // Phone number
                        Text(formattedPhoneNumber)
                            .font(.system(size: 24, weight: .semibold))

                        // Action buttons
                        HStack(spacing: 24) {
                            ActionButton(icon: "phone.fill", label: "Call") {
                                // Initiate call
                            }

                            ActionButton(icon: "star.fill", label: "Favorite") {
                                showingAddFavorite = true
                            }

                            ActionButton(icon: "square.and.arrow.up", label: "Share") {
                                sharePhoneNumber()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                // Call details
                Section {
                    DetailRow(
                        icon: "arrow.up.right",
                        label: "Direction",
                        value: call.callDirection.displayName
                    )

                    DetailRow(
                        icon: "checkmark.circle",
                        label: "Status",
                        value: call.callStatus.displayName,
                        valueColor: statusColor
                    )

                    DetailRow(
                        icon: "calendar",
                        label: "Date",
                        value: formattedDate
                    )

                    DetailRow(
                        icon: "clock",
                        label: "Time",
                        value: formattedTime
                    )

                    if let duration = call.durationSeconds, duration > 0 {
                        DetailRow(
                            icon: "timer",
                            label: "Duration",
                            value: formattedDuration(duration)
                        )
                    }
                } header: {
                    Text("Call Details")
                }

                // Technical details
                if let callSid = call.callSid {
                    Section {
                        DetailRow(
                            icon: "number",
                            label: "Call SID",
                            value: String(callSid.prefix(20)) + "..."
                        )
                    } header: {
                        Text("Technical")
                    }
                }

                // Delete button
                Section {
                    Button(role: .destructive) {
                        deleteCall()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete Call Record", systemImage: "trash")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Call Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingAddFavorite) {
                EditFavoriteSheet(
                    favorite: nil
                ) { favorite in
                    favorite.phoneNumber = call.phoneNumber
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var directionIcon: String {
        switch call.callDirection {
        case .outbound: return "phone.arrow.up.right.fill"
        case .inbound: return "phone.arrow.down.left.fill"
        }
    }

    private var statusColor: Color {
        switch call.callStatus {
        case .ended, .connected:
            return call.callDirection == .outbound ? .blue : .green
        case .failed:
            return .red
        case .initiating, .ringing:
            return .secondary
        }
    }

    private var formattedPhoneNumber: String {
        let digits = call.phoneNumber.filter { $0.isNumber }
        guard digits.count >= 10 else { return call.phoneNumber }

        if digits.count == 10 {
            let areaCode = String(digits.prefix(3))
            let middle = String(digits.dropFirst(3).prefix(3))
            let last = String(digits.dropFirst(6))
            return "(\(areaCode)) \(middle)-\(last)"
        } else if digits.count == 11 {
            let countryCode = String(digits.prefix(1))
            let areaCode = String(digits.dropFirst(1).prefix(3))
            let middle = String(digits.dropFirst(4).prefix(3))
            let last = String(digits.dropFirst(7).prefix(4))
            return "+\(countryCode) (\(areaCode)) \(middle)-\(last)"
        }
        return call.phoneNumber
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: call.startedAt)
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: call.startedAt)
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    // MARK: - Actions

    private func deleteCall() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        modelContext.delete(call)
        dismiss()
    }

    private func sharePhoneNumber() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        let activityVC = UIActivityViewController(
            activityItems: [call.phoneNumber],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

/// Detail row for call information
struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 24)

            Text(label)
                .font(.system(size: 16))
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 16))
                .foregroundColor(valueColor)
        }
    }
}

/// Action button for call detail actions
struct ActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            action()
        }) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.blue)
                    .frame(width: 50, height: 50)
                    .background(
                        Circle()
                            .fill(Color.blue.opacity(0.12))
                    )

                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.blue)
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: CallRecord.self, configurations: config)

    let call = CallRecord(
        direction: "outbound",
        phoneNumber: "5551234567",
        status: "ended",
        durationSeconds: 125
    )
    call.callSid = "CA1234567890abcdef1234567890abcdef"

    return CallDetailView(call: call)
        .modelContainer(container)
}
