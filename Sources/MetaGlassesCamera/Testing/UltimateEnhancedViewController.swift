import UIKit
import Combine
import Speech
import AVFoundation

/// Ultimate Enhanced UI with AI enhancement, voice commands, and live streaming
@MainActor
public class UltimateEnhancedViewController: UIViewController {

    // MARK: - Properties
    public var cameraManager: DualCameraManager?
    public var imageEnhancer: AIImageEnhancer?
    public var enableVoiceCommands: Bool = false
    public var enableLiveStream: Bool = false

    private let aiAnalyzer = AIVisionAnalyzer.shared
    private var cancellables = Set<AnyCancellable>()
    private var liveStreamTimer: Timer?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var currentStereoPair: StereoPair?
    private var isLiveStreaming = false

    // MARK: - UI Components

    private lazy var headerView: UIView = {
        let view = UIView()
        // Animated gradient background
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0).cgColor,
            UIColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 1.0).cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        view.layer.insertSublayer(gradientLayer, at: 0)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = "🧬 MetaGlasses 3D Vision"
        label.font = .systemFont(ofSize: 28, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "AI-Enhanced • Voice Control • Live Stream"
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(0.9)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var statusStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var statusIndicator: UIView = {
        let view = UIView()
        view.backgroundColor = .systemRed
        view.layer.cornerRadius = 6
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.text = "DISCONNECTED"
        label.font = .systemFont(ofSize: 13, weight: .bold)
        label.textColor = .systemRed
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var liveIndicator: UILabel = {
        let label = UILabel()
        label.text = "● LIVE"
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = .systemRed
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var voiceIndicator: UILabel = {
        let label = UILabel()
        label.text = "🎤 Listening..."
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .systemBlue
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var liveStreamView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.layer.cornerRadius = 12
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var liveStreamImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var cameraStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var leftCameraView: CameraPreviewView = {
        return CameraPreviewView(title: "📷 Navigation (AI Enhanced)", color: .systemBlue)
    }()

    private lazy var rightCameraView: CameraPreviewView = {
        return CameraPreviewView(title: "📷 Imaging (AI Enhanced)", color: .systemPurple)
    }()

    private lazy var captureButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "🎥 CAPTURE & ENHANCE"
        config.baseBackgroundColor = UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0)
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        config.buttonSize = .large
        config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 32, bottom: 16, trailing: 32)

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(captureButtonTapped), for: .touchUpInside)
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 4)
        button.layer.shadowRadius = 8
        button.layer.shadowOpacity = 0.3
        return button
    }()

    private lazy var enhancementLabel: UILabel = {
        let label = UILabel()
        label.text = "✨ AI Enhancement: OFF"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .gray
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var connectButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "🔌 Connect to Glasses"
        config.baseBackgroundColor = .systemGreen
        config.baseForegroundColor = .white
        config.cornerStyle = .medium

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(connectButtonTapped), for: .touchUpInside)
        return button
    }()

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()

        if enableVoiceCommands {
            setupVoiceCommands()
        }

        print("🚀 Ultimate Enhanced Mode: Voice=\(enableVoiceCommands), LiveStream=\(enableLiveStream)")
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Update gradient frame
        if let gradientLayer = headerView.layer.sublayers?.first as? CAGradientLayer {
            gradientLayer.frame = headerView.bounds
        }
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground

        // Add header
        view.addSubview(headerView)
        headerView.addSubview(titleLabel)
        headerView.addSubview(subtitleLabel)

        // Add status
        view.addSubview(statusStack)
        statusStack.addArrangedSubview(statusIndicator)
        statusStack.addArrangedSubview(statusLabel)
        statusStack.addArrangedSubview(liveIndicator)
        statusStack.addArrangedSubview(voiceIndicator)

        // Add connect button
        view.addSubview(connectButton)

        // Add live stream view (if enabled)
        if enableLiveStream {
            view.addSubview(liveStreamView)
            liveStreamView.addSubview(liveStreamImageView)
        }

        // Add camera views
        view.addSubview(cameraStackView)
        cameraStackView.addArrangedSubview(leftCameraView)
        cameraStackView.addArrangedSubview(rightCameraView)

        // Add capture button
        view.addSubview(captureButton)
        view.addSubview(enhancementLabel)

        setupConstraints()
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Header
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 120),

            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 50),

            subtitleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),

            // Status
            statusStack.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 16),
            statusStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            statusIndicator.widthAnchor.constraint(equalToConstant: 12),
            statusIndicator.heightAnchor.constraint(equalToConstant: 12),

            // Connect button
            connectButton.topAnchor.constraint(equalTo: statusStack.bottomAnchor, constant: 12),
            connectButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            connectButton.widthAnchor.constraint(equalToConstant: 200)
        ])

        // Live stream (if enabled)
        if enableLiveStream {
            NSLayoutConstraint.activate([
                liveStreamView.topAnchor.constraint(equalTo: connectButton.bottomAnchor, constant: 20),
                liveStreamView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
                liveStreamView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
                liveStreamView.heightAnchor.constraint(equalToConstant: 200),

                liveStreamImageView.topAnchor.constraint(equalTo: liveStreamView.topAnchor),
                liveStreamImageView.leadingAnchor.constraint(equalTo: liveStreamView.leadingAnchor),
                liveStreamImageView.trailingAnchor.constraint(equalTo: liveStreamView.trailingAnchor),
                liveStreamImageView.bottomAnchor.constraint(equalTo: liveStreamView.bottomAnchor),

                cameraStackView.topAnchor.constraint(equalTo: liveStreamView.bottomAnchor, constant: 20)
            ])
        } else {
            NSLayoutConstraint.activate([
                cameraStackView.topAnchor.constraint(equalTo: connectButton.bottomAnchor, constant: 20)
            ])
        }

        NSLayoutConstraint.activate([
            // Camera views
            cameraStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cameraStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            cameraStackView.heightAnchor.constraint(equalToConstant: 250),

            // Capture button
            captureButton.topAnchor.constraint(equalTo: cameraStackView.bottomAnchor, constant: 24),
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            // Enhancement label
            enhancementLabel.topAnchor.constraint(equalTo: captureButton.bottomAnchor, constant: 12),
            enhancementLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    // MARK: - Voice Commands

    private func setupVoiceCommands() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                if status == .authorized {
                    self?.startListening()
                    print("🎤 Voice commands enabled")
                } else {
                    print("⚠️ Speech recognition not authorized")
                }
            }
        }
    }

    private func startListening() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            voiceIndicator.isHidden = false
        } catch {
            print("⚠️ Audio engine failed to start: \(error)")
        }

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            if let result = result {
                let transcript = result.bestTranscription.formattedString.lowercased()
                self?.handleVoiceCommand(transcript)
            }

            if error != nil || result?.isFinal == true {
                self?.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self?.recognitionRequest = nil
                self?.recognitionTask = nil
            }
        }
    }

    private func handleVoiceCommand(_ transcript: String) {
        print("🎤 Heard: \(transcript)")

        if transcript.contains("take a picture") || transcript.contains("take picture") ||
           transcript.contains("capture") || transcript.contains("snap") {
            Task {
                await captureAndEnhance()
            }
        } else if transcript.contains("connect") {
            Task {
                await connect()
            }
        } else if transcript.contains("start streaming") || transcript.contains("start live") {
            startLiveStreaming()
        } else if transcript.contains("stop streaming") || transcript.contains("stop live") {
            stopLiveStreaming()
        }
    }

    // MARK: - Live Streaming

    private func startLiveStreaming() {
        guard !isLiveStreaming, let manager = cameraManager else { return }

        isLiveStreaming = true
        liveIndicator.isHidden = false

        print("📡 Starting live stream...")

        liveStreamTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updateLiveStream()
            }
        }
    }

    private func stopLiveStreaming() {
        isLiveStreaming = false
        liveIndicator.isHidden = true
        liveStreamTimer?.invalidate()
        liveStreamTimer = nil

        print("📡 Live stream stopped")
    }

    private func updateLiveStream() async {
        // Capture frame from glasses for live preview
        // In production, this would stream actual camera data
        // For now, we'll simulate with periodic captures

        guard let manager = cameraManager else { return }

        do {
            let leftData = try await manager.captureFromCamera(.navigation)
            if let leftImage = UIImage(data: leftData) {
                liveStreamImageView.image = leftImage
            }
        } catch {
            // Silent fail for live stream
        }
    }

    // MARK: - Actions

    @objc private func connectButtonTapped() {
        Task {
            await connect()
        }
    }

    private func connect() async {
        guard let manager = cameraManager else { return }

        statusLabel.text = "Connecting..."
        statusIndicator.backgroundColor = .systemYellow

        do {
            try await manager.connect()

            statusLabel.text = "🟢 CONNECTED"
            statusIndicator.backgroundColor = .systemGreen
            statusLabel.textColor = .systemGreen
            captureButton.isEnabled = true

            if enableLiveStream {
                startLiveStreaming()
            }

            print("✅ Connected to glasses!")
        } catch {
            statusLabel.text = "Connection Failed"
            statusIndicator.backgroundColor = .systemRed
            print("❌ Connection error: \(error)")
        }
    }

    @objc private func captureButtonTapped() {
        Task {
            await captureAndEnhance()
        }
    }

    private func captureAndEnhance() async {
        guard let manager = cameraManager else { return }

        captureButton.isEnabled = false
        enhancementLabel.text = "📸 Capturing..."
        enhancementLabel.textColor = .systemBlue

        do {
            // Capture stereo pair
            let stereoPair = try await manager.captureStereoPair()
            currentStereoPair = stereoPair

            enhancementLabel.text = "✨ AI Enhancing..."

            // AI Enhancement
            if let enhancer = imageEnhancer {
                let enhancedLeft = try await enhancer.enhance(stereoPair.leftImage)
                let enhancedRight = try await enhancer.enhance(stereoPair.rightImage)

                // Display enhanced images
                leftCameraView.imageView.image = enhancedLeft.enhanced
                rightCameraView.imageView.image = enhancedRight.enhanced

                enhancementLabel.text = "✅ AI Enhanced: \(enhancedLeft.improvements.joined(separator: ", "))"
                enhancementLabel.textColor = .systemGreen

                print("✨ AI Enhancement applied!")
                print("   Improvements: \(enhancedLeft.improvements)")
            } else {
                // No enhancement, just display
                leftCameraView.imageView.image = stereoPair.leftImage
                rightCameraView.imageView.image = stereoPair.rightImage

                enhancementLabel.text = "✅ Captured (No enhancement)"
                enhancementLabel.textColor = .systemGreen
            }

        } catch {
            enhancementLabel.text = "❌ Capture failed"
            enhancementLabel.textColor = .systemRed
            print("❌ Capture error: \(error)")
        }

        captureButton.isEnabled = true
    }
}

// MARK: - Camera Preview View

class CameraPreviewView: UIView {
    let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.backgroundColor = .systemGray6
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    init(title: String, color: UIColor) {
        super.init(frame: .zero)
        titleLabel.text = title
        titleLabel.textColor = color
        layer.borderColor = color.cgColor
        layer.borderWidth = 2
        layer.cornerRadius = 12
        clipsToBounds = true

        addSubview(titleLabel)
        addSubview(imageView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            imageView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
