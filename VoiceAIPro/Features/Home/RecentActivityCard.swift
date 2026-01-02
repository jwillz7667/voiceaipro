import SwiftUI
import SwiftData

/// Compact recent calls card
struct RecentActivityCard: View {
    @Query(
        filter: #Predicate<CallRecord> { _ in true },
        sort: \CallRecord.startedAt,
        order: .reverse
    ) private var allCalls: [CallRecord]

    var onSelectCall: ((CallRecord) -> Void)?
    var onCallNumber: ((String) -> Void)?

    private var recentCalls: [CallRecord] {
        Array(allCalls.prefix(3))
    }

    var body: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Text("Recent")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    if !allCalls.isEmpty {
                        NavigationLink(destination: CallHistoryView()) {
                            HStack(spacing: 4) {
                                Text("See All")
                                    .font(.system(size: 13, weight: .medium))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(.blue)
                        }
                    }
                }

                // Recent calls list
                if recentCalls.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(recentCalls.enumerated()), id: \.element.id) { index, call in
                            RecentCallRow(call: call) {
                                onCallNumber?(call.phoneNumber)
                            }

                            if index < recentCalls.count - 1 {
                                Divider()
                                    .padding(.leading, 40)
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "phone.badge.waveform")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
                Text("No recent calls")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 16)
            Spacer()
        }
    }
}

/// Individual recent call row
struct RecentCallRow: View {
    let call: CallRecord
    var onCall: (() -> Void)?

    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            onCall?()
        }) {
            HStack(spacing: 12) {
                // Direction icon
                Image(systemName: directionIcon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(directionColor)
                    .frame(width: 28)

                // Call info
                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedPhoneNumber)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)

                    Text(call.callStatus.displayName)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Time ago
                Text(timeAgo)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                // Call button
                Image(systemName: "phone.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var directionIcon: String {
        switch call.callDirection {
        case .outbound:
            return "phone.arrow.up.right.fill"
        case .inbound:
            return "phone.arrow.down.left.fill"
        }
    }

    private var directionColor: Color {
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

    private var timeAgo: String {
        let now = Date()
        let components = Calendar.current.dateComponents(
            [.minute, .hour, .day],
            from: call.startedAt,
            to: now
        )

        if let days = components.day, days > 0 {
            return days == 1 ? "Yesterday" : "\(days)d ago"
        } else if let hours = components.hour, hours > 0 {
            return "\(hours)h ago"
        } else if let minutes = components.minute, minutes > 0 {
            return "\(minutes)m ago"
        } else {
            return "Just now"
        }
    }
}

#Preview {
    NavigationStack {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            RecentActivityCard()
                .modelContainer(for: [CallRecord.self, FavoriteContact.self], inMemory: true)
                .padding()
        }
    }
}
