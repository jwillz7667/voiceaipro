import SwiftUI
import SwiftData

/// Full call history view
struct CallHistoryView: View {
    @Query(sort: \CallRecord.startedAt, order: .reverse) private var calls: [CallRecord]
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var selectedFilter: HistoryFilter = .all
    @State private var selectedCall: CallRecord?

    private var filteredCalls: [CallRecord] {
        var result = calls

        // Apply search
        if !searchText.isEmpty {
            result = result.filter { call in
                call.phoneNumber.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Apply filter
        switch selectedFilter {
        case .all:
            break
        case .incoming:
            result = result.filter { $0.callDirection == .inbound }
        case .outgoing:
            result = result.filter { $0.callDirection == .outbound }
        case .missed:
            result = result.filter { $0.callStatus == .failed }
        }

        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if calls.isEmpty {
                    emptyState
                } else {
                    List {
                        // Filter picker
                        Section {
                            Picker("Filter", selection: $selectedFilter) {
                                ForEach(HistoryFilter.allCases, id: \.self) { filter in
                                    Text(filter.displayName).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                        }

                        // Grouped by date
                        ForEach(groupedCalls.keys.sorted().reversed(), id: \.self) { date in
                            Section {
                                ForEach(groupedCalls[date] ?? []) { call in
                                    CallHistoryRow(call: call)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedCall = call
                                        }
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) {
                                                deleteCall(call)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                        .swipeActions(edge: .leading) {
                                            Button {
                                                addToFavorites(call)
                                            } label: {
                                                Label("Favorite", systemImage: "star")
                                            }
                                            .tint(.yellow)
                                        }
                                }
                            } header: {
                                Text(sectionHeader(for: date))
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .searchable(text: $searchText, prompt: "Search calls")
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if !calls.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(role: .destructive) {
                                clearAllHistory()
                            } label: {
                                Label("Clear All", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(item: $selectedCall) { call in
                CallDetailView(call: call)
            }
        }
    }

    private var groupedCalls: [Date: [CallRecord]] {
        Dictionary(grouping: filteredCalls) { call in
            Calendar.current.startOfDay(for: call.startedAt)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Calls Yet",
            systemImage: "phone.badge.waveform",
            description: Text("Your call history will appear here")
        )
    }

    private func sectionHeader(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }

    private func deleteCall(_ call: CallRecord) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        modelContext.delete(call)
    }

    private func clearAllHistory() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        for call in calls {
            modelContext.delete(call)
        }
    }

    private func addToFavorites(_ call: CallRecord) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        let favorite = FavoriteContact(
            name: call.phoneNumber,
            phoneNumber: call.phoneNumber
        )
        modelContext.insert(favorite)
    }
}

/// History filter options
enum HistoryFilter: CaseIterable {
    case all
    case incoming
    case outgoing
    case missed

    var displayName: String {
        switch self {
        case .all: return "All"
        case .incoming: return "Incoming"
        case .outgoing: return "Outgoing"
        case .missed: return "Missed"
        }
    }
}

/// Individual call history row
struct CallHistoryRow: View {
    let call: CallRecord

    var body: some View {
        HStack(spacing: 14) {
            // Direction icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: directionIcon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(statusColor)
            }

            // Call info
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedPhoneNumber)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)

                HStack(spacing: 6) {
                    Text(call.callStatus.displayName)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)

                    if let duration = call.durationSeconds, duration > 0 {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(formattedDuration(duration))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Time
            VStack(alignment: .trailing, spacing: 4) {
                Text(formattedTime)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
        .padding(.vertical, 4)
    }

    private var directionIcon: String {
        switch call.callDirection {
        case .outbound:
            return "phone.arrow.up.right.fill"
        case .inbound:
            return "phone.arrow.down.left.fill"
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
        }
        return call.phoneNumber
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: call.startedAt)
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }
        return "\(secs)s"
    }
}

#Preview {
    CallHistoryView()
        .modelContainer(for: [CallRecord.self, FavoriteContact.self], inMemory: true)
}
