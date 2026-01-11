import UIKit
import Combine

/// AI-Enhanced Test View Controller with RAG, CAG, MCP, and Facial Recognition
/// Works in simulator with mock camera implementation
public class TestDualCaptureViewController: UIViewController {

    // MARK: - Properties

    private let cameraManager = TestDualCameraManager()
    private let aiAnalyzer = AIVisionAnalyzer.shared
    private let depthEstimator = AIDepthEstimator.shared
    private var cancellables = Set<AnyCancellable>()

    private var currentAnalysis: AIVisionAnalyzer.SceneAnalysis?

    // MARK: - UI Components

    private lazy var headerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemOrange.withAlphaComponent(0.2)
        view.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "🧪 TEST MODE - AI Enhanced"
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 14, weight: .bold)
        label.textColor = .systemOrange
        label.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        return view
    }()

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.text = "Not Connected (Simulator)"
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .systemRed
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var connectButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Connect (Mock)"
        config.baseBackgroundColor = .systemBlue
        config.cornerStyle = .medium

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(connectButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var stereoPreviewStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var leftImageView = createImageView(title: "Navigation (Mock)")
    private lazy var rightImageView = createImageView(title: "Imaging (Mock)")

    private lazy var captureButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "🤖 Capture with AI Analysis"
        config.baseBackgroundColor = .systemGreen
        config.cornerStyle = .medium
        config.buttonSize = .large

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isEnabled = false
        button.addTarget(self, action: #selector(captureWithAIButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var aiAnalysisView: UITextView = {
        let textView = UITextView()
        textView.backgroundColor = .systemGray6
        textView.layer.cornerRadius = 8
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isEditable = false
        textView.text = "AI Analysis will appear here...\n\n" +
                        "Features:\n" +
                        "🤖 Facial Recognition with Depth\n" +
                        "🔍 RAG (Retrieval Augmented Generation)\n" +
                        "🧠 CAG (Contextual Augmented Generation)\n" +
                        "🔌 MCP (Model Context Protocol) Servers\n" +
                        "📊 Object Detection\n" +
                        "📝 Text Recognition (OCR)\n" +
                        "🎯 Scene Classification"
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupBindings()
        showWelcomeMessage()
    }

    // MARK: - Setup

    private func setupUI() {
        title = "🧪 AI-Enhanced Test Mode"
        view.backgroundColor = .systemBackground

        stereoPreviewStack.addArrangedSubview(leftImageView)
        stereoPreviewStack.addArrangedSubview(rightImageView)

        view.addSubview(headerView)
        view.addSubview(statusLabel)
        view.addSubview(connectButton)
        view.addSubview(stereoPreviewStack)
        view.addSubview(captureButton)
        view.addSubview(aiAnalysisView)
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            // Header
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 30),

            // Status
            statusLabel.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Connect Button
            connectButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            connectButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            connectButton.widthAnchor.constraint(equalToConstant: 200),

            // Stereo Preview
            stereoPreviewStack.topAnchor.constraint(equalTo: connectButton.bottomAnchor, constant: 20),
            stereoPreviewStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stereoPreviewStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stereoPreviewStack.heightAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.3),

            // Capture Button
            captureButton.topAnchor.constraint(equalTo: stereoPreviewStack.bottomAnchor, constant: 16),
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.widthAnchor.constraint(equalToConstant: 280),

            // AI Analysis View
            aiAnalysisView.topAnchor.constraint(equalTo: captureButton.bottomAnchor, constant: 16),
            aiAnalysisView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            aiAnalysisView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            aiAnalysisView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),

            // Activity Indicator
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: aiAnalysisView.centerYAnchor)
        ])
    }

    private func createImageView(title: String) -> UIView {
        let container = UIView()
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .systemGray6
        imageView.layer.cornerRadius = 8
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textAlignment = .center
        label.textColor = .systemGray
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(imageView)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: label.topAnchor, constant: -4),

            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    private func setupBindings() {
        cameraManager.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                self?.updateConnectionStatus(isConnected)
            }
            .store(in: &cancellables)

        cameraManager.$capturedStereoPairs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pairs in
                self?.updateStereoPreview(pairs)
            }
            .store(in: &cancellables)

        cameraManager.$isCapturing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isCapturing in
                self?.updateCapturingStatus(isCapturing)
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func connectButtonTapped() {
        Task {
            activityIndicator.startAnimating()
            do {
                try await cameraManager.connectToGlasses()
                updateAIAnalysisText("✅ Connected to mock glasses\n🤖 AI systems ready")
            } catch {
                showError(error.localizedDescription)
            }
            activityIndicator.stopAnimating()
        }
    }

    @objc private func captureWithAIButtonTapped() {
        Task {
            do {
                updateAIAnalysisText("📸 Capturing stereo pair...\n")

                // Capture stereo images
                let stereoPair = try await cameraManager.captureStereoImage()

                updateAIAnalysisText("🤖 Running comprehensive AI analysis...\n" +
                                    "• Facial Recognition\n" +
                                    "• Object Detection\n" +
                                    "• Text Recognition\n" +
                                    "• Scene Classification\n" +
                                    "• Depth Estimation\n" +
                                    "• RAG Context Retrieval\n" +
                                    "• CAG Narrative Generation\n" +
                                    "• MCP Server Queries\n")

                // Run comprehensive AI analysis
                let analysis = try await aiAnalyzer.analyzeScene(in: stereoPair)
                currentAnalysis = analysis

                // Generate depth map
                let depthMap = try await depthEstimator.estimateDepth(from: stereoPair)

                // Display results
                displayAnalysisResults(analysis, depthMap: depthMap)

            } catch {
                showError("AI Analysis failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - UI Updates

    private func updateConnectionStatus(_ isConnected: Bool) {
        statusLabel.text = isConnected ? "✅ Connected (Mock Mode)" : "Not Connected"
        statusLabel.textColor = isConnected ? .systemGreen : .systemRed
        captureButton.isEnabled = isConnected

        var config = connectButton.configuration
        config?.title = isConnected ? "Disconnect" : "Connect (Mock)"
        connectButton.configuration = config
    }

    private func updateStereoPreview(_ pairs: [StereoPair]) {
        if let latest = pairs.last {
            (leftImageView.subviews.first as? UIImageView)?.image = latest.leftImage
            (rightImageView.subviews.first as? UIImageView)?.image = latest.rightImage
        }
    }

    private func updateCapturingStatus(_ isCapturing: Bool) {
        if isCapturing {
            activityIndicator.startAnimating()
            captureButton.isEnabled = false
        } else {
            activityIndicator.stopAnimating()
            captureButton.isEnabled = cameraManager.isConnected
        }
    }

    private func updateAIAnalysisText(_ text: String) {
        aiAnalysisView.text = text
    }

    private func displayAnalysisResults(_ analysis: AIVisionAnalyzer.SceneAnalysis, depthMap: UIImage?) {
        var output = "🎉 AI ANALYSIS COMPLETE\n"
        output += "═══════════════════════\n\n"

        output += "📊 SCENE: \(analysis.sceneClassification)\n\n"

        if !analysis.faces.isEmpty {
            output += "👤 FACES DETECTED: \(analysis.faces.count)\n"
            for (idx, face) in analysis.faces.enumerated() {
                output += "Face \(idx + 1): \(Int(face.confidence * 100))% confidence\n"
            }
            output += "\n"
        }

        if !analysis.objects.isEmpty {
            output += "🎯 OBJECTS DETECTED:\n"
            for obj in analysis.objects.prefix(5) {
                output += "• \(obj.label) (\(Int(obj.confidence * 100))%)\n"
            }
            output += "\n"
        }

        if !analysis.text.isEmpty {
            output += "📝 TEXT RECOGNIZED:\n"
            for text in analysis.text.prefix(3) {
                output += "• \(text.text)\n"
            }
            output += "\n"
        }

        output += "💡 AI FEATURES:\n"
        output += "• Facial Recognition\n"
        output += "• Object Detection\n"
        output += "• Text Recognition (OCR)\n"
        output += "• Scene Classification\n\n"

        if let depthImage = depthMap {
            output += "📏 Depth Map Generated: \(Int(depthImage.size.width))x\(Int(depthImage.size.height))\n"
        }

        updateAIAnalysisText(output)
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func showWelcomeMessage() {
        let alert = UIAlertController(
            title: "🧪 AI-Enhanced Test Mode",
            message: """
            This version includes:

            🤖 Advanced AI Analysis
            • Facial Recognition with Depth
            • RAG (Retrieval Augmented Generation)
            • CAG (Contextual Augmented Generation)
            • MCP (Model Context Protocol) Servers
            • Object Detection
            • Text Recognition (OCR)
            • Scene Understanding

            Works in iOS Simulator!
            """,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Got it!", style: .default))
        present(alert, animated: true)
    }
}
