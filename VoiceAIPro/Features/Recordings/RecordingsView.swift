import SwiftUI
import SwiftData
import AVFoundation
import Combine

/// View showing all saved call recordings
struct RecordingsView: View {
    @Query(sort: \RecordingMetadata.createdAt, order: .reverse) private var recordings: [RecordingMetadata]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var container: DIContainer

    @State private var selectedRecording: RecordingMetadata?
    @State private var isPlaying = false
    @State private var currentlyPlayingId: UUID?
    @State private var showingDeleteConfirmation = false
    @State private var recordingToDelete: RecordingMetadata?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if recordings.isEmpty {
                    emptyState
                        .onAppear {
                            print("📱📱📱 EMPTY STATE VISIBLE - VIEW LOADED 📱📱📱")
                        }
                } else {
                    List {
                        ForEach(recordings) { recording in
                            RecordingRow(
                                recording: recording,
                                isPlaying: currentlyPlayingId == recording.id && isPlaying,
                                isDownloading: currentlyPlayingId == recording.id && isLoading,
                                onPlay: { togglePlayback(recording) },
                                onDelete: { confirmDelete(recording) }
                            )
                        }
                        .onDelete(perform: deleteRecordings)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Recordings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if !recordings.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            refreshRecordings()
                        } label: {
                            if isLoading {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                    }
                }
            }
            .alert("Delete Recording?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let recording = recordingToDelete {
                        deleteRecording(recording)
                    }
                }
            } message: {
                Text("This will permanently delete the recording.")
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
            .onAppear {
                print("📱📱📱 RECORDINGS VIEW APPEARED 📱📱📱")
                print("📱📱📱 container: \(container)")
                print("📱📱📱 modelContext: \(modelContext)")
            }
            .task {
                print("📱📱📱 TASK STARTING 📱📱📱")
                await fetchRecordingsFromServer()
            }
            .refreshable {
                await fetchRecordingsFromServer()
            }
        }
    }

    private func fetchRecordingsFromServer() async {
        print("📱 [RecordingsView] ========== FETCH STARTED ==========")
        isLoading = true

        do {
            let serverRecordings = try await container.apiClient.getRecordings(limit: 50, offset: 0)
            print("📱 [RecordingsView] API returned \(serverRecordings.count) recordings")

            if let first = serverRecordings.first {
                print("📱 [RecordingsView] First: \(first)")
            }

            for recordingData in serverRecordings {
                guard let idString = recordingData["id"] as? String,
                      let recordingId = UUID(uuidString: idString) else {
                    print("📱 [RecordingsView] ❌ Bad ID: \(recordingData["id"] ?? "nil")")
                    continue
                }

                // Skip if exists
                let exists = recordings.contains { $0.id == recordingId }
                if exists { continue }

                // Parse file_size (comes as string from postgres bigint)
                let fileSize: Int64
                if let str = recordingData["file_size"] as? String, let val = Int64(str) {
                    fileSize = val
                } else if let num = recordingData["file_size"] as? NSNumber {
                    fileSize = num.int64Value
                } else {
                    fileSize = 0
                }

                // Parse duration
                let duration: Int
                if let num = recordingData["duration"] as? NSNumber {
                    duration = num.intValue
                } else {
                    duration = 0
                }

                let metadata = RecordingMetadata(
                    id: recordingId,
                    callSessionId: UUID(uuidString: recordingData["call_session_id"] as? String ?? "") ?? UUID(),
                    callSid: recordingData["call_sid"] as? String,
                    durationSeconds: duration,
                    fileSizeBytes: fileSize,
                    format: recordingData["format"] as? String ?? "wav",
                    sampleRate: recordingData["sample_rate"] as? Int,
                    channels: recordingData["channels"] as? Int,
                    createdAt: parseDate(recordingData["created_at"] as? String) ?? Date(),
                    syncedAt: Date(),
                    hasTranscript: recordingData["has_transcript"] as? Bool ?? false
                )

                print("📱 [RecordingsView] ✅ Inserting \(recordingId)")
                modelContext.insert(metadata)
            }

            try modelContext.save()
            print("📱 [RecordingsView] ✅ Saved. Count: \(recordings.count)")

        } catch {
            print("📱 [RecordingsView] ❌ ERROR: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Recordings Yet",
            systemImage: "waveform.circle",
            description: Text("Call recordings will appear here when recording is enabled")
        )
    }

    private func togglePlayback(_ recording: RecordingMetadata) {
        if currentlyPlayingId == recording.id && isPlaying {
            // Stop playback
            AudioPlayer.shared.stop()
            isPlaying = false
            currentlyPlayingId = nil
        } else {
            // Start playback - download first if needed
            if let url = recording.localURL {
                playRecording(recording, url: url)
            } else {
                // Need to download first
                downloadAndPlay(recording)
            }
        }
    }

    private func playRecording(_ recording: RecordingMetadata, url: URL) {
        AudioPlayer.shared.play(url: url) { finished in
            if finished {
                isPlaying = false
                currentlyPlayingId = nil
            }
        }
        isPlaying = true
        currentlyPlayingId = recording.id
    }

    private func downloadAndPlay(_ recording: RecordingMetadata) {
        // Show loading state
        currentlyPlayingId = recording.id
        isLoading = true

        Task {
            do {
                print("📱 [RecordingsView] Downloading recording: \(recording.id)")
                let localURL = try await container.apiClient.downloadRecording(id: recording.id)
                print("📱 [RecordingsView] Downloaded to: \(localURL.path)")

                // Update the recording's local path
                recording.setLocalPath(localURL.path)
                try modelContext.save()

                // Now play it
                await MainActor.run {
                    isLoading = false
                    playRecording(recording, url: localURL)
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    currentlyPlayingId = nil
                    errorMessage = "Failed to download recording: \(error.localizedDescription)"
                    print("📱 [RecordingsView] ❌ Download failed: \(error)")
                }
            }
        }
    }

    private func confirmDelete(_ recording: RecordingMetadata) {
        recordingToDelete = recording
        showingDeleteConfirmation = true
    }

    private func deleteRecording(_ recording: RecordingMetadata) {
        // Stop playback if playing this recording
        if currentlyPlayingId == recording.id {
            AudioPlayer.shared.stop()
            isPlaying = false
            currentlyPlayingId = nil
        }

        // Clear local file
        recording.clearLocalDownload()

        // Delete from database
        modelContext.delete(recording)

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    private func deleteRecordings(at offsets: IndexSet) {
        for index in offsets {
            let recording = recordings[index]
            deleteRecording(recording)
        }
    }

    private func refreshRecordings() {
        print("📱 [RecordingsView] ========== REFRESH STARTED ==========")
        print("📱 [RecordingsView] Current @Query count: \(recordings.count)")
        print("📱 [RecordingsView] ModelContext: \(modelContext)")
        isLoading = true
        Task {
            do {
                // container.apiClient returns [[String: Any]] - parse each dict
                print("📱 [RecordingsView] Fetching from API...")
                let serverRecordings = try await container.apiClient.getRecordings(limit: 50, offset: 0)
                print("📱 [RecordingsView] API returned \(serverRecordings.count) recordings")

                if serverRecordings.isEmpty {
                    print("📱 [RecordingsView] ⚠️ Server returned EMPTY recordings array")
                    isLoading = false
                    return
                }

                // Debug: print first recording to see structure
                if let first = serverRecordings.first {
                    print("📱 [RecordingsView] First recording keys: \(first.keys.sorted())")
                    print("📱 [RecordingsView] First recording data: \(first)")
                }

                var insertedCount = 0
                var skippedCount = 0
                var failedCount = 0

                // Sync with local database
                for (index, recordingData) in serverRecordings.enumerated() {
                    // Parse from dictionary and save if not exists
                    guard let idString = recordingData["id"] as? String,
                          let recordingId = UUID(uuidString: idString) else {
                        print("📱 [RecordingsView] ❌ [\(index)] Failed to parse recording ID")
                        print("📱 [RecordingsView]   id value: \(recordingData["id"] ?? "nil") type: \(type(of: recordingData["id"]))")
                        failedCount += 1
                        continue
                    }

                    // Check if already exists in @Query results
                    let existsInQuery = recordings.contains { $0.id == recordingId }

                    // Also check via direct fetch to be sure
                    let fetchDescriptor = FetchDescriptor<RecordingMetadata>(
                        predicate: #Predicate { $0.id == recordingId }
                    )
                    let existsInDB = (try? modelContext.fetchCount(fetchDescriptor)) ?? 0 > 0

                    if existsInQuery || existsInDB {
                        skippedCount += 1
                        continue
                    }

                    // Get file_size - server may send as string, int, or double (NSNumber)
                    let fileSizeValue: Int64
                    if let fileSizeString = recordingData["file_size"] as? String,
                       let parsed = Int64(fileSizeString) {
                        fileSizeValue = parsed
                    } else if let fileSizeInt = recordingData["file_size"] as? Int {
                        fileSizeValue = Int64(fileSizeInt)
                    } else if let fileSizeInt64 = recordingData["file_size"] as? Int64 {
                        fileSizeValue = fileSizeInt64
                    } else if let fileSizeDouble = recordingData["file_size"] as? Double {
                        fileSizeValue = Int64(fileSizeDouble)
                    } else {
                        print("📱 [RecordingsView] ⚠️ [\(index)] Could not parse file_size: \(recordingData["file_size"] ?? "nil")")
                        fileSizeValue = 0
                    }

                    // Get duration - server may send as int or double
                    let durationValue: Int
                    if let durationInt = recordingData["duration"] as? Int {
                        durationValue = durationInt
                    } else if let durationDouble = recordingData["duration"] as? Double {
                        durationValue = Int(durationDouble)
                    } else {
                        durationValue = 0
                    }

                    // Parse created_at date
                    let createdAtValue: Date
                    if let createdAtString = recordingData["created_at"] as? String {
                        createdAtValue = parseDate(createdAtString) ?? Date()
                    } else {
                        createdAtValue = Date()
                    }

                    let metadata = RecordingMetadata(
                        id: recordingId,
                        callSessionId: UUID(uuidString: recordingData["call_session_id"] as? String ?? "") ?? UUID(),
                        callSid: recordingData["call_sid"] as? String,
                        durationSeconds: durationValue,
                        fileSizeBytes: fileSizeValue,
                        format: recordingData["format"] as? String ?? "wav",
                        sampleRate: recordingData["sample_rate"] as? Int,
                        channels: recordingData["channels"] as? Int,
                        createdAt: createdAtValue,
                        syncedAt: Date(),
                        hasTranscript: recordingData["has_transcript"] as? Bool ?? false
                    )

                    print("📱 [RecordingsView] ✅ [\(index)] Inserting: id=\(recordingId), duration=\(durationValue)s, size=\(fileSizeValue)")
                    modelContext.insert(metadata)
                    insertedCount += 1
                }

                print("📱 [RecordingsView] Summary: inserted=\(insertedCount), skipped=\(skippedCount), failed=\(failedCount)")

                if insertedCount > 0 {
                    print("📱 [RecordingsView] Saving context...")
                    try modelContext.save()
                    print("📱 [RecordingsView] ✅ Save complete!")
                }

                // After save, check @Query count
                print("📱 [RecordingsView] Post-save @Query count: \(recordings.count)")

            } catch {
                errorMessage = "Failed to refresh recordings: \(error.localizedDescription)"
                print("📱 [RecordingsView] ❌ ERROR: \(error)")
            }
            isLoading = false
            print("📱 [RecordingsView] ========== REFRESH COMPLETE ==========")
        }
    }

    private func parseDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: dateString)
    }
}

/// Individual recording row
struct RecordingRow: View {
    let recording: RecordingMetadata
    let isPlaying: Bool
    let isDownloading: Bool
    let onPlay: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Play button
            Button(action: onPlay) {
                ZStack {
                    Circle()
                        .fill(isPlaying ? Color.blue : Color.blue.opacity(0.15))
                        .frame(width: 44, height: 44)

                    if isDownloading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : (recording.isDownloaded ? "play.fill" : "arrow.down.circle"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isPlaying ? .white : .blue)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isDownloading)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(recording.formattedDate)
                        .font(.system(size: 16, weight: .medium))

                    if recording.hasTranscript {
                        Image(systemName: "text.bubble.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Text(recording.formattedDuration)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text(recording.formattedFileSize)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Text(recording.audioDetails)
                    .font(.system(size: 12))
                    .foregroundColor(Color(.tertiaryLabel))
            }

            Spacer()

            // Status indicators
            VStack(alignment: .trailing, spacing: 4) {
                if recording.isDownloaded {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                }

                if recording.isSynced {
                    Image(systemName: "checkmark.icloud.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Audio Player

/// Simple audio player for recordings
class AudioPlayer: NSObject, ObservableObject {
    static let shared = AudioPlayer()

    private var player: AVAudioPlayer?
    private var completion: ((Bool) -> Void)?

    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    private override init() {
        super.init()
    }

    func play(url: URL, completion: @escaping (Bool) -> Void) {
        stop()

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            player?.play()

            self.completion = completion
            isPlaying = true
            duration = player?.duration ?? 0

            // Start time updates
            startTimeUpdates()
        } catch {
            print("Failed to play audio: \(error)")
            completion(false)
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        completion?(false)
        completion = nil
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func resume() {
        player?.play()
        isPlaying = true
    }

    private func startTimeUpdates() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self, self.isPlaying else {
                timer.invalidate()
                return
            }
            self.currentTime = self.player?.currentTime ?? 0
        }
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        currentTime = 0
        completion?(true)
        completion = nil
    }
}

#Preview {
    RecordingsView()
        .modelContainer(for: RecordingMetadata.self, inMemory: true)
        .environmentObject(DIContainer.shared)
}
