import SwiftUI
import SwiftData

/// Full call history view
struct CallHistoryView: View {
    @Query(sort: \CallRecord.startedAt, order: .reverse) private var calls: [CallRecord]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var container: DIContainer

    @State private var searchText = ""
    @State private var selectedFilter: HistoryFilter = .all
    @State private var selectedCall: CallRecord?
    @State private var isLoading = false
    @State private var syncError: String?

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
            .task {
                await syncCallHistory()
            }
            .refreshable {
                await syncCallHistory()
            }
            .overlay {
                if isLoading && calls.isEmpty {
                    ProgressView("Loading history...")
                }
            }
        }
    }

    /// Sync call history from server to local SwiftData
    private func syncCallHistory() async {
        print("📱 [CallHistoryView] ========== SYNC STARTED ==========")
        print("📱 [CallHistoryView] Current @Query count: \(calls.count)")
        print("📱 [CallHistoryView] DataManager exists: \(container.dataManager != nil)")
        print("📱 [CallHistoryView] ModelContext: \(modelContext)")

        guard !isLoading else {
            print("📱 [CallHistoryView] Already loading, skipping")
            return
        }
        isLoading = true
        syncError = nil

        do {
            // container.apiClient returns [[String: Any]] - parse each dict to CallHistoryItem
            print("📱 [CallHistoryView] Fetching from API...")
            let serverCalls = try await container.apiClient.getCallHistory(limit: 100, offset: 0)
            print("📱 [CallHistoryView] API returned \(serverCalls.count) calls")

            if serverCalls.isEmpty {
                print("📱 [CallHistoryView] ⚠️ Server returned EMPTY calls array")
                isLoading = false
                return
            }

            // Debug: print first call to see structure
            if let first = serverCalls.first {
                print("📱 [CallHistoryView] First call keys: \(first.keys.sorted())")
                print("📱 [CallHistoryView] First call data: \(first)")
            }

            var historyItems: [CallHistoryItem] = []
            var parseFailures: [(index: Int, reason: String)] = []

            for (index, callData) in serverCalls.enumerated() {
                if let item = CallHistoryItem(from: callData) {
                    historyItems.append(item)
                } else {
                    // Debug why parsing failed
                    let id = callData["id"]
                    let callSid = callData["call_sid"]
                    let direction = callData["direction"]
                    let phoneNumber = callData["phone_number"]
                    let status = callData["status"]
                    let startedAt = callData["started_at"]

                    var missing: [String] = []
                    if id == nil { missing.append("id") }
                    if callSid == nil { missing.append("call_sid") }
                    if direction == nil { missing.append("direction") }
                    if phoneNumber == nil { missing.append("phone_number") }
                    if status == nil { missing.append("status") }
                    if startedAt == nil { missing.append("started_at") }

                    let reason = missing.isEmpty ? "date parse failed" : "missing: \(missing.joined(separator: ", "))"
                    parseFailures.append((index, reason))
                    print("📱 [CallHistoryView] ❌ [\(index)] Parse failed: \(reason)")
                }
            }

            print("📱 [CallHistoryView] Parsed \(historyItems.count)/\(serverCalls.count) items")
            if !parseFailures.isEmpty {
                print("📱 [CallHistoryView] ⚠️ \(parseFailures.count) parse failures")
            }

            // Sync parsed items to SwiftData
            if let dm = container.dataManager {
                print("📱 [CallHistoryView] Syncing \(historyItems.count) items to DataManager...")
                try await dm.syncCallHistory(with: historyItems)
                print("📱 [CallHistoryView] ✅ Sync complete!")
            } else {
                print("📱 [CallHistoryView] ❌ DataManager is nil! Falling back to direct insert...")

                // Fallback: insert directly into modelContext
                var insertedCount = 0
                for item in historyItems {
                    // Check if exists
                    let itemId = item.id
                    let fetchDescriptor = FetchDescriptor<CallRecord>(
                        predicate: #Predicate { $0.id == itemId }
                    )
                    let exists = (try? modelContext.fetchCount(fetchDescriptor)) ?? 0 > 0

                    if !exists {
                        let record = CallRecord(from: item)
                        modelContext.insert(record)
                        insertedCount += 1
                    }
                }

                if insertedCount > 0 {
                    try modelContext.save()
                    print("📱 [CallHistoryView] ✅ Fallback insert: \(insertedCount) records")
                }
            }

        } catch {
            syncError = error.localizedDescription
            print("📱 [CallHistoryView] ❌ ERROR: \(error)")
        }

        isLoading = false
        print("📱 [CallHistoryView] Post-sync @Query count: \(calls.count)")
        print("📱 [CallHistoryView] ========== SYNC COMPLETE ==========")
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
