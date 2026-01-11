import UIKit
import Combine

/// Enhanced Test UI with automatic mock data, animations, and polished design
@MainActor
public class EnhancedTestDualCaptureViewController: UIViewController {
    
    // MARK: - Properties
    private let cameraManager = TestDualCameraManager()
    private let aiAnalyzer = AIVisionAnalyzer.shared
    private var cancellables = Set<AnyCancellable>()
    private var autoConnectTimer: Timer?
    private var currentAnalysis: AIVisionAnalyzer.SceneAnalysis?
    
    // MARK: - UI Components
    
    private lazy var headerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0)
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
        label.text = "AI-Powered Stereoscopic Capture"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(0.9)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var statusIndicator: UIView = {
        let view = UIView()
        view.backgroundColor = .systemGreen
        view.layer.cornerRadius = 6
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.text = "🟢 CONNECTED"
        label.font = .systemFont(ofSize: 13, weight: .bold)
        label.textColor = .systemGreen
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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
        return CameraPreviewView(title: "📷 Navigation", color: .systemBlue)
    }()
    
    private lazy var rightCameraView: CameraPreviewView = {
        return CameraPreviewView(title: "📷 Imaging", color: .systemPurple)
    }()
    
    private lazy var captureButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "🎥 CAPTURE 3D IMAGE"
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
    
    private lazy var aiAnalysisLabel: UILabel = {
        let label = UILabel()
        label.text = "🤖 AI Analysis"
        label.font = .systemFont(ofSize: 18, weight: .bold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var analysisTextView: UITextView = {
        let textView = UITextView()
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isEditable = false
        textView.backgroundColor = UIColor.secondarySystemBackground
        textView.layer.cornerRadius = 12
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.text = "Waiting for capture...\n\nPress the button above to capture a 3D image with AI analysis."
        return textView
    }()
    
    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    // MARK: - Lifecycle
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupBindings()
        autoConnect()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        view.addSubview(headerView)
        headerView.addSubview(titleLabel)
        headerView.addSubview(subtitleLabel)
        view.addSubview(statusIndicator)
        view.addSubview(statusLabel)
        view.addSubview(cameraStackView)
        
        cameraStackView.addArrangedSubview(leftCameraView)
        cameraStackView.addArrangedSubview(rightCameraView)
        
        view.addSubview(captureButton)
        view.addSubview(activityIndicator)
        view.addSubview(aiAnalysisLabel)
        view.addSubview(analysisTextView)
        
        NSLayoutConstraint.activate([
            // Header
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 140),
            
            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            
            subtitleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            
            // Status
            statusIndicator.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            statusIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: -40),
            statusIndicator.widthAnchor.constraint(equalToConstant: 12),
            statusIndicator.heightAnchor.constraint(equalToConstant: 12),
            
            statusLabel.centerYAnchor.constraint(equalTo: statusIndicator.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: statusIndicator.trailingAnchor, constant: 6),
            
            // Camera Stack
            cameraStackView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 20),
            cameraStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            cameraStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            cameraStackView.heightAnchor.constraint(equalToConstant: 200),
            
            // Capture Button
            captureButton.topAnchor.constraint(equalTo: cameraStackView.bottomAnchor, constant: 24),
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            // Activity Indicator
            activityIndicator.centerXAnchor.constraint(equalTo: captureButton.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            
            // AI Analysis
            aiAnalysisLabel.topAnchor.constraint(equalTo: captureButton.bottomAnchor, constant: 24),
            aiAnalysisLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            
            analysisTextView.topAnchor.constraint(equalTo: aiAnalysisLabel.bottomAnchor, constant: 8),
            analysisTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            analysisTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            analysisTextView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
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
                if let latest = pairs.last {
                    self?.displayStereoPair(latest)
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Auto Connect
    
    private func autoConnect() {
        Task {
            do {
                analysisTextView.text = "🔄 Connecting to mock glasses...\n\nInitializing AI systems..."
                try await cameraManager.connectToGlasses()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.analysisTextView.text = """
                    ✅ Connected Successfully!
                    
                    🎯 Ready to capture 3D images
                    🤖 AI analysis enabled
                    📷 Dual camera system active
                    
                    Press the button below to start!
                    """
                }
            } catch {
                analysisTextView.text = "❌ Connection failed: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Actions
    
    @objc private func captureButtonTapped() {
        Task {
            captureButton.isEnabled = false
            activityIndicator.startAnimating()
            
            analysisTextView.text = "📸 Capturing from dual cameras...\n⏳ Please wait..."
            
            do {
                let stereoPair = try await cameraManager.captureStereoImage()
                
                analysisTextView.text += "\n\n✅ Capture complete!\n🧠 Running AI analysis..."
                
                let analysis = try await aiAnalyzer.analyzeScene(in: stereoPair)
                let depthMap = try await AIDepthEstimator.shared.estimateDepth(from: stereoPair)
                
                displayAnalysis(analysis, depthMap: depthMap)
                
            } catch {
                analysisTextView.text = "❌ Capture failed: \(error.localizedDescription)"
            }
            
            captureButton.isEnabled = true
            activityIndicator.stopAnimating()
        }
    }
    
    // MARK: - Display
    
    private func updateConnectionStatus(_ isConnected: Bool) {
        UIView.animate(withDuration: 0.3) {
            self.statusIndicator.backgroundColor = isConnected ? .systemGreen : .systemRed
            self.statusLabel.text = isConnected ? "🟢 CONNECTED" : "🔴 DISCONNECTED"
            self.statusLabel.textColor = isConnected ? .systemGreen : .systemRed
        }
        
        if isConnected {
            statusIndicator.layer.add(pulseAnimation(), forKey: "pulse")
        }
    }
    
    private func displayStereoPair(_ pair: StereoPair) {
        leftCameraView.setImage(pair.leftImage)
        rightCameraView.setImage(pair.rightImage)
        
        // Animate the image appearance
        leftCameraView.alpha = 0
        rightCameraView.alpha = 0
        
        UIView.animate(withDuration: 0.5, delay: 0, options: .curveEaseOut) {
            self.leftCameraView.alpha = 1
            self.rightCameraView.alpha = 1
        }
    }
    
    private func displayAnalysis(_ analysis: AIVisionAnalyzer.SceneAnalysis, depthMap: UIImage?) {
        var output = "🎉 AI ANALYSIS COMPLETE\n"
        output += String(repeating: "═", count: 40) + "\n\n"
        
        output += "📊 Scene: \(analysis.sceneClassification)\n"
        output += "⏰ Timestamp: \(formatDate(analysis.timestamp))\n\n"
        
        if !analysis.faces.isEmpty {
            output += "👤 Faces: \(analysis.faces.count) detected\n"
            for (idx, face) in analysis.faces.prefix(3).enumerated() {
                output += "   • Face \(idx + 1): \(Int(face.confidence * 100))% confidence\n"
            }
            output += "\n"
        }
        
        if !analysis.objects.isEmpty {
            output += "🎯 Objects:\n"
            for obj in analysis.objects.prefix(5) {
                output += "   • \(obj.label) (\(Int(obj.confidence * 100))%)\n"
            }
            output += "\n"
        }
        
        if !analysis.text.isEmpty {
            output += "📝 Text detected: \(analysis.text.count) regions\n"
            for text in analysis.text.prefix(3) {
                output += "   • \"\(text.text)\"\n"
            }
            output += "\n"
        }
        
        output += "🧬 AI Features Active:\n"
        output += "   ✓ Facial Recognition\n"
        output += "   ✓ Object Detection\n"
        output += "   ✓ OCR Text Recognition\n"
        output += "   ✓ Scene Classification\n"
        output += "   ✓ Depth Estimation\n"
        
        if let depth = depthMap {
            output += "\n📏 Depth Map: \(Int(depth.size.width))×\(Int(depth.size.height))px"
        }
        
        analysisTextView.text = output
    }
    
    // MARK: - Helpers
    
    private func pulseAnimation() -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.duration = 1.0
        animation.fromValue = 1.0
        animation.toValue = 1.3
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.autoreverses = true
        animation.repeatCount = .infinity
        return animation
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - Camera Preview View

class CameraPreviewView: UIView {
    private let titleLabel: UILabel
    private let imageView: UIImageView
    private let placeholderIcon: UIImageView
    private let color: UIColor
    
    init(title: String, color: UIColor) {
        self.color = color
        self.titleLabel = UILabel()
        self.imageView = UIImageView()
        self.placeholderIcon = UIImageView()
        super.init(frame: .zero)
        
        setupView(title: title)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView(title: String) {
        backgroundColor = UIColor.secondarySystemBackground
        layer.cornerRadius = 16
        layer.borderWidth = 2
        layer.borderColor = color.cgColor
        clipsToBounds = true
        
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        titleLabel.textColor = color
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        placeholderIcon.image = UIImage(systemName: "camera.fill")
        placeholderIcon.tintColor = color.withAlphaComponent(0.3)
        placeholderIcon.contentMode = .scaleAspectFit
        placeholderIcon.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(imageView)
        addSubview(placeholderIcon)
        addSubview(titleLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            
            imageView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            
            placeholderIcon.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholderIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            placeholderIcon.widthAnchor.constraint(equalToConstant: 50),
            placeholderIcon.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    func setImage(_ image: UIImage) {
        imageView.image = image
        placeholderIcon.isHidden = true
    }
}
