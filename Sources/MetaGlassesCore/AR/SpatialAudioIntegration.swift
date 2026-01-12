import Foundation
import AVFoundation
import ARKit
import CoreLocation
import Combine
import simd

// MARK: - Spatial Audio Integration
/// Advanced spatial audio system with 3D audio cues, direction-based navigation, and AR context
@MainActor
public class SpatialAudioIntegration: NSObject, ObservableObject {

    // MARK: - Published Properties
    @Published public var isPlaying = false
    @Published public var spatialAudioEnabled = true
    @Published public var audioSources: [SpatialAudioSource] = []
    @Published public var activeNavigationCue: NavigationCue?
    @Published public var ambientSoundscape: AmbientSoundscape?

    // MARK: - Private Properties
    private var audioEngine: AVAudioEngine
    private var audioEnvironment: AVAudioEnvironmentNode
    private var audioPlayerNodes: [UUID: AVAudioPlayerNode] = [:]
    private var audioFiles: [UUID: AVAudioFile] = [:]
    private var cancellables = Set<AnyCancellable>()

    // AR Integration
    private var arSession: ARSession?
    private var lastCameraPosition: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    private var lastCameraOrientation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))

    // Audio recording for spatial capture
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?

    // MARK: - Data Models

    public struct SpatialAudioSource: Identifiable {
        public let id: UUID
        public let name: String
        public var position: SIMD3<Float>
        public let audioURL: URL
        public var volume: Float
        public var isLooping: Bool
        public var isPlaying: Bool
        public let timestamp: Date

        public init(
            id: UUID = UUID(),
            name: String,
            position: SIMD3<Float>,
            audioURL: URL,
            volume: Float = 1.0,
            isLooping: Bool = false
        ) {
            self.id = id
            self.name = name
            self.position = position
            self.audioURL = audioURL
            self.volume = volume
            self.isLooping = isLooping
            self.isPlaying = false
            self.timestamp = Date()
        }
    }

    public struct NavigationCue {
        public let targetPosition: SIMD3<Float>
        public let targetName: String
        public let audioType: NavigationAudioType
        public var distance: Float
        public var direction: SIMD3<Float>

        public enum NavigationAudioType {
            case beacon // Continuous beeping that gets faster as you approach
            case voice  // Voice directions
            case chime  // Musical chime that changes pitch based on direction
            case pulse  // Pulsing sound
        }
    }

    public struct AmbientSoundscape {
        public let id: UUID
        public var layers: [AudioLayer]
        public var intensity: Float

        public struct AudioLayer {
            public let audioURL: URL
            public let volume: Float
            public let spatialBlend: Float // 0 = 2D, 1 = full 3D
        }
    }

    public struct SpatialRecording {
        public let id: UUID
        public let audioURL: URL
        public let capturePosition: SIMD3<Float>
        public let captureOrientation: simd_quatf
        public let duration: TimeInterval
        public let timestamp: Date
    }

    // MARK: - Initialization

    public override init() {
        self.audioEngine = AVAudioEngine()
        self.audioEnvironment = AVAudioEnvironmentNode()
        super.init()
        setupAudioEngine()
        setupAudioSession()
    }

    public convenience init(arSession: ARSession) {
        self.init()
        self.arSession = arSession
    }

    private func setupAudioEngine() {
        // Attach environment node
        audioEngine.attach(audioEnvironment)

        // Connect environment to output
        audioEngine.connect(
            audioEnvironment,
            to: audioEngine.mainMixerNode,
            format: audioEnvironment.outputFormat(forBus: 0)
        )

        // Configure spatial audio environment
        audioEnvironment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        audioEnvironment.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)

        // Set rendering algorithm
        audioEnvironment.renderingAlgorithm = .HRTF // Head-Related Transfer Function for best spatial audio

        // Set distance attenuation
        audioEnvironment.distanceAttenuationParameters.distanceAttenuationModel = .inverse
        audioEnvironment.distanceAttenuationParameters.referenceDistance = 1.0
        audioEnvironment.distanceAttenuationParameters.maximumDistance = 50.0
        audioEnvironment.distanceAttenuationParameters.rolloffFactor = 1.0

        print("🎧 Audio engine configured with HRTF spatial audio")
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
            try session.setActive(true)
            print("✅ Audio session configured")
        } catch {
            print("❌ Failed to setup audio session: \(error)")
        }
    }

    // MARK: - Audio Engine Control

    public func startAudioEngine() {
        guard !audioEngine.isRunning else { return }

        do {
            try audioEngine.start()
            isPlaying = true
            print("▶️ Audio engine started")
        } catch {
            print("❌ Failed to start audio engine: \(error)")
        }
    }

    public func stopAudioEngine() {
        audioEngine.stop()
        isPlaying = false
        print("⏹️ Audio engine stopped")
    }

    // MARK: - Spatial Audio Source Management

    public func addAudioSource(
        name: String,
        at position: SIMD3<Float>,
        audioURL: URL,
        volume: Float = 1.0,
        isLooping: Bool = false,
        autoPlay: Bool = true
    ) -> SpatialAudioSource? {

        let source = SpatialAudioSource(
            name: name,
            position: position,
            audioURL: audioURL,
            volume: volume,
            isLooping: isLooping
        )

        audioSources.append(source)

        // Load audio file
        do {
            let audioFile = try AVAudioFile(forReading: audioURL)
            audioFiles[source.id] = audioFile

            // Create player node
            let playerNode = AVAudioPlayerNode()
            audioEngine.attach(playerNode)
            audioPlayerNodes[source.id] = playerNode

            // Connect player to environment
            audioEngine.connect(
                playerNode,
                to: audioEnvironment,
                format: audioFile.processingFormat
            )

            // Set 3D position
            audioEnvironment.position(forPlayer: playerNode) = AVAudio3DPoint(
                x: position.x,
                y: position.y,
                z: position.z
            )

            if autoPlay {
                playAudioSource(id: source.id)
            }

            print("🔊 Added spatial audio source: \(name) at \(position)")
            return source

        } catch {
            print("❌ Failed to load audio file: \(error)")
            return nil
        }
    }

    public func playAudioSource(id: UUID) {
        guard let playerNode = audioPlayerNodes[id],
              let audioFile = audioFiles[id],
              let index = audioSources.firstIndex(where: { $0.id == id }) else {
            return
        }

        var source = audioSources[index]
        source.isPlaying = true
        audioSources[index] = source

        playerNode.stop()

        if source.isLooping {
            playerNode.scheduleFile(audioFile, at: nil, completionHandler: { [weak self] in
                self?.playAudioSource(id: id)
            })
        } else {
            playerNode.scheduleFile(audioFile, at: nil)
        }

        playerNode.volume = source.volume
        playerNode.play()

        startAudioEngine()
    }

    public func stopAudioSource(id: UUID) {
        guard let playerNode = audioPlayerNodes[id],
              let index = audioSources.firstIndex(where: { $0.id == id }) else {
            return
        }

        var source = audioSources[index]
        source.isPlaying = false
        audioSources[index] = source

        playerNode.stop()
    }

    public func removeAudioSource(id: UUID) {
        stopAudioSource(id: id)

        audioSources.removeAll { $0.id == id }

        if let playerNode = audioPlayerNodes[id] {
            audioEngine.detach(playerNode)
            audioPlayerNodes.removeValue(forKey: id)
        }

        audioFiles.removeValue(forKey: id)
    }

    public func updateAudioSourcePosition(id: UUID, position: SIMD3<Float>) {
        guard let playerNode = audioPlayerNodes[id],
              let index = audioSources.firstIndex(where: { $0.id == id }) else {
            return
        }

        var source = audioSources[index]
        source.position = position
        audioSources[index] = source

        audioEnvironment.position(forPlayer: playerNode) = AVAudio3DPoint(
            x: position.x,
            y: position.y,
            z: position.z
        )
    }

    // MARK: - AR Integration

    public func updateListenerPosition(from arSession: ARSession) {
        guard let frame = arSession.currentFrame else { return }

        let cameraTransform = frame.camera.transform
        let cameraPosition = SIMD3<Float>(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)

        // Update listener position
        audioEnvironment.listenerPosition = AVAudio3DPoint(
            x: cameraPosition.x,
            y: cameraPosition.y,
            z: cameraPosition.z
        )

        // Extract orientation from camera transform
        let forward = -SIMD3<Float>(cameraTransform.columns.2.x, cameraTransform.columns.2.y, cameraTransform.columns.2.z)
        let up = SIMD3<Float>(cameraTransform.columns.1.x, cameraTransform.columns.1.y, cameraTransform.columns.1.z)

        // Calculate yaw, pitch, roll
        let yaw = atan2(forward.x, forward.z) * 180 / .pi
        let pitch = asin(-forward.y) * 180 / .pi

        audioEnvironment.listenerAngularOrientation = AVAudio3DAngularOrientation(
            yaw: Float(yaw),
            pitch: Float(pitch),
            roll: 0
        )

        lastCameraPosition = cameraPosition
    }

    // MARK: - Navigation Audio Cues

    public func startNavigationCue(to position: SIMD3<Float>, targetName: String, type: NavigationCue.NavigationAudioType = .beacon) {
        let direction = normalize(position - lastCameraPosition)
        let distance = simd_distance(position, lastCameraPosition)

        activeNavigationCue = NavigationCue(
            targetPosition: position,
            targetName: targetName,
            audioType: type,
            distance: distance,
            direction: direction
        )

        // Start playing navigation audio
        Task {
            await playNavigationAudio(type: type)
        }

        print("🧭 Started navigation cue to: \(targetName)")
    }

    public func stopNavigationCue() {
        activeNavigationCue = nil
        // Stop navigation audio playback
        print("🧭 Stopped navigation cue")
    }

    private func playNavigationAudio(type: NavigationCue.NavigationAudioType) async {
        guard let cue = activeNavigationCue else { return }

        switch type {
        case .beacon:
            await playBeaconSound(distance: cue.distance)
        case .voice:
            await playVoiceDirection(direction: cue.direction, distance: cue.distance, targetName: cue.targetName)
        case .chime:
            await playDirectionalChime(direction: cue.direction)
        case .pulse:
            await playPulseSound(distance: cue.distance)
        }
    }

    private func playBeaconSound(distance: Float) async {
        // Generate beeping sound with frequency based on distance
        let frequency = max(0.5, 5.0 / distance) // Faster beeps when closer
        print("🔔 Playing beacon at frequency: \(frequency) Hz (distance: \(distance)m)")
    }

    private func playVoiceDirection(direction: SIMD3<Float>, distance: Float, targetName: String) async {
        let directionText = getDirectionText(direction: direction)
        let distanceText = String(format: "%.1f meters", distance)
        print("🗣️ Voice: \(targetName) is \(distanceText) \(directionText)")
    }

    private func playDirectionalChime(direction: SIMD3<Float>) async {
        // Pitch varies based on horizontal angle
        let angle = atan2(direction.x, direction.z)
        let pitch = 440 + (angle * 100) // Base frequency 440Hz (A4)
        print("🎵 Playing chime at \(pitch) Hz")
    }

    private func playPulseSound(distance: Float) async {
        let intensity = 1.0 / max(distance, 1.0)
        print("💓 Playing pulse with intensity: \(intensity)")
    }

    private func getDirectionText(direction: SIMD3<Float>) -> String {
        let angle = atan2(direction.x, direction.z) * 180 / .pi

        switch angle {
        case -22.5..<22.5: return "ahead"
        case 22.5..<67.5: return "ahead right"
        case 67.5..<112.5: return "right"
        case 112.5..<157.5: return "behind right"
        case -67.5 ..< -22.5: return "ahead left"
        case -112.5 ..< -67.5: return "left"
        case -157.5 ..< -112.5: return "behind left"
        default: return "behind"
        }
    }

    // MARK: - Ambient Soundscape

    public func setAmbientSoundscape(layers: [AmbientSoundscape.AudioLayer], intensity: Float = 1.0) {
        ambientSoundscape = AmbientSoundscape(id: UUID(), layers: layers, intensity: intensity)

        for layer in layers {
            _ = addAudioSource(
                name: "Ambient_\(UUID().uuidString)",
                at: SIMD3<Float>(0, 0, 0),
                audioURL: layer.audioURL,
                volume: layer.volume * intensity,
                isLooping: true,
                autoPlay: true
            )
        }

        print("🌅 Set ambient soundscape with \(layers.count) layers")
    }

    public func clearAmbientSoundscape() {
        guard let soundscape = ambientSoundscape else { return }

        // Remove all ambient audio sources
        for source in audioSources where source.name.hasPrefix("Ambient_") {
            removeAudioSource(id: source.id)
        }

        ambientSoundscape = nil
        print("🌅 Cleared ambient soundscape")
    }

    // MARK: - Spatial Audio Recording

    public func startSpatialRecording() {
        guard let arSession = arSession,
              let frame = arSession.currentFrame else {
            print("⚠️ Cannot start recording without AR session")
            return
        }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        recordingURL = documentsPath.appendingPathComponent("spatial_recording_\(Date().timeIntervalSince1970).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL!, settings: settings)
            audioRecorder?.record()

            // Store spatial metadata
            lastCameraPosition = SIMD3<Float>(frame.camera.transform.columns.3.x, frame.camera.transform.columns.3.y, frame.camera.transform.columns.3.z)

            print("🎤 Started spatial audio recording")
        } catch {
            print("❌ Failed to start recording: \(error)")
        }
    }

    public func stopSpatialRecording() -> SpatialRecording? {
        audioRecorder?.stop()

        guard let url = recordingURL else { return nil }

        let recording = SpatialRecording(
            id: UUID(),
            audioURL: url,
            capturePosition: lastCameraPosition,
            captureOrientation: lastCameraOrientation,
            duration: audioRecorder?.currentTime ?? 0,
            timestamp: Date()
        )

        audioRecorder = nil
        recordingURL = nil

        print("🎤 Stopped spatial recording: \(recording.duration)s")
        return recording
    }

    // MARK: - Audio Analysis

    public func analyzeAudioSource(id: UUID) -> AudioAnalysis? {
        guard let audioFile = audioFiles[id] else { return nil }

        let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
        let channelCount = Int(audioFile.processingFormat.channelCount)
        let sampleRate = audioFile.processingFormat.sampleRate

        return AudioAnalysis(
            duration: duration,
            channelCount: channelCount,
            sampleRate: sampleRate,
            fileSize: 0 // Would need to calculate from URL
        )
    }

    public struct AudioAnalysis {
        public let duration: TimeInterval
        public let channelCount: Int
        public let sampleRate: Double
        public let fileSize: Int64
    }

    // MARK: - Cleanup

    deinit {
        stopAudioEngine()
        cancellables.forEach { $0.cancel() }
    }
}

// MARK: - Audio Session Observer

extension SpatialAudioIntegration {

    public func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            stopAudioEngine()
            print("⚠️ Audio session interrupted")
        case .ended:
            startAudioEngine()
            print("✅ Audio session interruption ended")
        @unknown default:
            break
        }
    }
}
