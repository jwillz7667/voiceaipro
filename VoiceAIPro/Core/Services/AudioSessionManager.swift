import Foundation
import AVFoundation
import Combine

/// Manages AVAudioSession configuration for VoIP calling
/// Handles audio routing, interruptions, and session lifecycle
class AudioSessionManager: ObservableObject {
    // MARK: - Singleton

    static let shared = AudioSessionManager()

    // MARK: - Published Properties

    /// Current audio route description
    @Published private(set) var currentRoute: AVAudioSessionRouteDescription

    /// Whether speaker is enabled
    @Published private(set) var isSpeakerEnabled: Bool = false

    /// Whether bluetooth is connected
    @Published private(set) var isBluetoothConnected: Bool = false

    /// Whether headphones are connected
    @Published private(set) var isHeadphonesConnected: Bool = false

    /// Whether session is active
    @Published private(set) var isActive: Bool = false

    // MARK: - Private Properties

    /// The shared audio session
    private let audioSession = AVAudioSession.sharedInstance()

    /// Observer for route changes
    private var routeChangeObserver: NSObjectProtocol?

    /// Observer for interruptions
    private var interruptionObserver: NSObjectProtocol?

    /// Observer for media services reset
    private var mediaServicesResetObserver: NSObjectProtocol?

    /// Cancellables
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Callbacks

    /// Called when audio route changes
    var onRouteChange: ((AVAudioSession.RouteChangeReason) -> Void)?

    /// Called when audio is interrupted
    var onInterruption: ((Bool) -> Void)? // true = began, false = ended

    /// Called when media services are reset
    var onMediaServicesReset: (() -> Void)?

    // MARK: - Initialization

    private init() {
        self.currentRoute = audioSession.currentRoute
        setupObservers()
        updateRouteStatus()
    }

    deinit {
        removeObservers()
    }

    // MARK: - Session Configuration

    /// Configure audio session for VoIP calling
    func configureForVoIP() throws {
        try audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [
                .allowBluetooth,
                .allowBluetoothA2DP,
                .defaultToSpeaker,
                .mixWithOthers
            ]
        )

        // Set preferred settings
        try audioSession.setPreferredSampleRate(Double(Constants.Audio.sampleRate))
        try audioSession.setPreferredIOBufferDuration(Constants.Audio.bufferDuration)

        updateRouteStatus()
    }

    /// Configure audio session for playback only (recordings)
    func configureForPlayback() throws {
        try audioSession.setCategory(
            .playback,
            mode: .default,
            options: [.mixWithOthers]
        )

        updateRouteStatus()
    }

    /// Activate the audio session
    func activateSession() throws {
        try audioSession.setActive(true, options: [.notifyOthersOnDeactivation])
        isActive = true
        updateRouteStatus()
    }

    /// Deactivate the audio session
    func deactivateSession() throws {
        try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
        isActive = false
    }

    // MARK: - Audio Routing

    /// Enable or disable speaker output
    func setSpeakerEnabled(_ enabled: Bool) throws {
        if enabled {
            try audioSession.overrideOutputAudioPort(.speaker)
        } else {
            try audioSession.overrideOutputAudioPort(.none)
        }
        isSpeakerEnabled = enabled
        updateRouteStatus()
    }

    /// Get the current audio route
    func getCurrentRoute() -> AVAudioSessionRouteDescription {
        return audioSession.currentRoute
    }

    /// Get available audio inputs
    func availableInputs() -> [AVAudioSessionPortDescription] {
        return audioSession.availableInputs ?? []
    }

    /// Set preferred input
    func setPreferredInput(_ input: AVAudioSessionPortDescription?) throws {
        try audioSession.setPreferredInput(input)
    }

    /// Get available audio outputs
    func availableOutputs() -> [AVAudioSessionPortDescription] {
        return audioSession.currentRoute.outputs
    }

    // MARK: - Audio Properties

    /// Current input gain
    var inputGain: Float {
        return audioSession.inputGain
    }

    /// Set input gain (0.0 to 1.0)
    func setInputGain(_ gain: Float) throws {
        guard audioSession.isInputGainSettable else {
            throw AudioSessionError.inputGainNotSettable
        }
        try audioSession.setInputGain(gain)
    }

    /// Current output volume
    var outputVolume: Float {
        return audioSession.outputVolume
    }

    /// Sample rate
    var sampleRate: Double {
        return audioSession.sampleRate
    }

    /// IO buffer duration
    var ioBufferDuration: TimeInterval {
        return audioSession.ioBufferDuration
    }

    /// Input latency
    var inputLatency: TimeInterval {
        return audioSession.inputLatency
    }

    /// Output latency
    var outputLatency: TimeInterval {
        return audioSession.outputLatency
    }

    // MARK: - Private Methods

    private func setupObservers() {
        let notificationCenter = NotificationCenter.default

        // Route change observer
        routeChangeObserver = notificationCenter.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }

        // Interruption observer
        interruptionObserver = notificationCenter.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }

        // Media services reset observer
        mediaServicesResetObserver = notificationCenter.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMediaServicesReset()
        }
    }

    private func removeObservers() {
        let notificationCenter = NotificationCenter.default

        if let observer = routeChangeObserver {
            notificationCenter.removeObserver(observer)
        }
        if let observer = interruptionObserver {
            notificationCenter.removeObserver(observer)
        }
        if let observer = mediaServicesResetObserver {
            notificationCenter.removeObserver(observer)
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        updateRouteStatus()
        currentRoute = audioSession.currentRoute
        onRouteChange?(reason)

        // Log route change
        switch reason {
        case .newDeviceAvailable:
            print("[AudioSession] New device available")
        case .oldDeviceUnavailable:
            print("[AudioSession] Old device unavailable")
        case .categoryChange:
            print("[AudioSession] Category changed")
        case .override:
            print("[AudioSession] Route override")
        case .wakeFromSleep:
            print("[AudioSession] Wake from sleep")
        case .noSuitableRouteForCategory:
            print("[AudioSession] No suitable route")
        case .routeConfigurationChange:
            print("[AudioSession] Route configuration changed")
        default:
            print("[AudioSession] Route changed: \(reason.rawValue)")
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            // Interruption began (e.g., phone call)
            isActive = false
            onInterruption?(true)
            print("[AudioSession] Interruption began")

        case .ended:
            // Interruption ended
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    // Should resume playback
                    try? activateSession()
                }
            }
            onInterruption?(false)
            print("[AudioSession] Interruption ended")

        @unknown default:
            break
        }
    }

    private func handleMediaServicesReset() {
        // Media services were reset - need to reconfigure
        print("[AudioSession] Media services reset")

        isActive = false
        updateRouteStatus()
        onMediaServicesReset?()

        // Attempt to reconfigure
        do {
            try configureForVoIP()
        } catch {
            print("[AudioSession] Failed to reconfigure after reset: \(error)")
        }
    }

    private func updateRouteStatus() {
        let route = audioSession.currentRoute

        // Check for Bluetooth
        isBluetoothConnected = route.outputs.contains { output in
            output.portType == .bluetoothA2DP ||
            output.portType == .bluetoothHFP ||
            output.portType == .bluetoothLE
        }

        // Check for headphones
        isHeadphonesConnected = route.outputs.contains { output in
            output.portType == .headphones ||
            output.portType == .headsetMic
        }

        // Check for speaker
        isSpeakerEnabled = route.outputs.contains { output in
            output.portType == .builtInSpeaker
        }

        currentRoute = route
    }
}

// MARK: - Audio Session Errors

enum AudioSessionError: LocalizedError {
    case configurationFailed
    case activationFailed
    case inputGainNotSettable
    case routeChangeFailed

    var errorDescription: String? {
        switch self {
        case .configurationFailed:
            return "Failed to configure audio session"
        case .activationFailed:
            return "Failed to activate audio session"
        case .inputGainNotSettable:
            return "Input gain cannot be set on this device"
        case .routeChangeFailed:
            return "Failed to change audio route"
        }
    }
}

// MARK: - Audio Route Description Extension

extension AVAudioSessionRouteDescription {
    /// Description of current input
    var inputDescription: String {
        inputs.map { $0.portName }.joined(separator: ", ")
    }

    /// Description of current output
    var outputDescription: String {
        outputs.map { $0.portName }.joined(separator: ", ")
    }

    /// Icon for current output type
    var outputIcon: String {
        guard let output = outputs.first else { return "speaker.wave.2" }

        switch output.portType {
        case .builtInSpeaker:
            return "speaker.wave.3"
        case .builtInReceiver:
            return "phone"
        case .headphones, .headsetMic:
            return "headphones"
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            return "airpodspro"
        case .carAudio:
            return "car"
        case .airPlay:
            return "airplayvideo"
        default:
            return "speaker.wave.2"
        }
    }
}
