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
                } else {
                    List {
                        ForEach(recordings) { recording in
                            RecordingRow(
                                recording: recording,
                                isPlaying: currentlyPlayingId == recording.id && isPlaying,
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
        }
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
            // Start playback
            if let url = recording.localURL {
                AudioPlayer.shared.play(url: url) { finished in
                    if finished {
                        isPlaying = false
                        currentlyPlayingId = nil
                    }
                }
                isPlaying = true
                currentlyPlayingId = recording.id
            } else {
                errorMessage = "Recording file not available locally"
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
        isLoading = true
        Task {
            do {
                let serverRecordings = try await container.apiClient.getRecordings(limit: 50, offset: 0)
                // Sync with local database
                for recordingData in serverRecordings {
                    // Parse from dictionary and save if not exists
                    guard let idString = recordingData["id"] as? String,
                          let recordingId = UUID(uuidString: idString) else { continue }

                    let existing = recordings.first { $0.id == recordingId }
                    if existing == nil {
                        let metadata = RecordingMetadata(
                            id: recordingId,
                            callSessionId: UUID(), // Placeholder - will be linked later if call exists
                            callSid: recordingData["call_sid"] as? String,
                            durationSeconds: recordingData["duration"] as? Int ?? 0,
                            fileSizeBytes: Int64(recordingData["file_size"] as? Int ?? 0),
                            format: recordingData["format"] as? String ?? "wav",
                            sampleRate: recordingData["sample_rate"] as? Int,
                            channels: recordingData["channels"] as? Int,
                            createdAt: parseDate(recordingData["created_at"] as? String) ?? Date(),
                            syncedAt: Date(),
                            hasTranscript: recordingData["has_transcript"] as? Bool ?? false
                        )
                        modelContext.insert(metadata)
                    }
                }
                try? modelContext.save()
            } catch {
                errorMessage = "Failed to refresh recordings: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    private func parseDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateString)
    }
}

/// Individual recording row
struct RecordingRow: View {
    let recording: RecordingMetadata
    let isPlaying: Bool
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

                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isPlaying ? .white : .blue)
                }
            }
            .buttonStyle(.plain)

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
