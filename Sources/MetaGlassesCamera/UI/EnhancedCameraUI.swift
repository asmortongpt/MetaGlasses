import SwiftUI
import AVFoundation
import Vision

/// Enhanced Camera UI with AI overlays, gesture controls, and real-time suggestions
/// Production-ready camera interface with beautiful animations and user feedback
@MainActor
public struct EnhancedCameraUI: View {

    // MARK: - State Management
    @StateObject private var cameraManager = AdvancedCameraManager()
    @StateObject private var gestureRecognizer = CameraGestureRecognizer()
    @StateObject private var aiOverlay = AIOverlayManager()

    @State private var captureMode: CaptureMode = .photo
    @State private var showingGallery = false
    @State private var showingSettings = false
    @State private var aiSuggestion: String? = nil
    @State private var detectedObjects: [DetectedObject] = []
    @State private var zoomLevel: CGFloat = 1.0
    @State private var flashMode: FlashMode = .auto
    @State private var isCapturing = false
    @State private var showCaptureAnimation = false
    @State private var recentCaptureCount = 0

    @Environment(\.dismiss) var dismiss

    // MARK: - Body
    public var body: some View {
        ZStack {
            // Camera Preview Layer
            CameraPreviewLayer(session: cameraManager.captureSession)
                .edgesIgnoringSafeArea(.all)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            handlePinchZoom(value)
                        }
                )
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            handleSwipeGesture(value)
                        }
                )
                .onTapGesture(count: 2) {
                    handleDoubleTap()
                }
                .onTapGesture {
                    handleSingleTap()
                }

            // AI Detection Overlays
            AIDetectionOverlayView(
                detectedObjects: detectedObjects,
                frameSize: UIScreen.main.bounds.size
            )

            // Top Controls Bar
            topControlsBar
                .padding(.top, 50)

            // AI Suggestion Banner
            if let suggestion = aiSuggestion {
                aiSuggestionBanner(suggestion)
                    .padding(.top, 120)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Gesture Feedback Overlay
            if gestureRecognizer.isActive {
                gestureOverlay
            }

            // Bottom Controls
            VStack {
                Spacer()
                bottomControlsPanel
                    .padding(.bottom, 40)
            }

            // Capture Animation Flash
            if showCaptureAnimation {
                Rectangle()
                    .fill(Color.white)
                    .opacity(0.8)
                    .edgesIgnoringSafeArea(.all)
                    .transition(.opacity)
            }

            // Focus Indicator
            if let focusPoint = cameraManager.focusPoint {
                FocusIndicatorView(point: focusPoint)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            setupCamera()
            startAIDetection()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .sheet(isPresented: $showingGallery) {
            SmartGalleryView()
        }
        .sheet(isPresented: $showingSettings) {
            CameraSettingsView(cameraManager: cameraManager)
        }
    }

    // MARK: - Top Controls Bar
    private var topControlsBar: some View {
        HStack(spacing: 16) {
            // Close Button
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                    )
            }

            Spacer()

            // Mode Indicator
            modePillIndicator

            Spacer()

            // Settings Button
            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                    )
            }
        }
        .padding(.horizontal, 20)
    }

    private var modePillIndicator: some View {
        HStack(spacing: 12) {
            Image(systemName: captureMode.icon)
                .font(.callout)
            Text(captureMode.displayName)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - AI Suggestion Banner
    private func aiSuggestionBanner(_ suggestion: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.yellow, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(suggestion)
                .font(.subheadline)
                .foregroundColor(.white)
                .lineLimit(2)

            Spacer()

            Button(action: {
                withAnimation(.spring()) {
                    aiSuggestion = nil
                }
            }) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
        )
        .padding(.horizontal, 20)
    }

    // MARK: - Gesture Overlay
    private var gestureOverlay: some View {
        VStack {
            Spacer()

            HStack(spacing: 20) {
                GestureIndicatorView(
                    icon: gestureRecognizer.currentGesture.icon,
                    label: gestureRecognizer.currentGesture.displayName
                )
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            )
            .padding(.bottom, 200)
        }
    }

    // MARK: - Bottom Controls Panel
    private var bottomControlsPanel: some View {
        VStack(spacing: 24) {
            // Mode Selector
            captureModeSelector

            // Main Controls Row
            HStack(spacing: 40) {
                // Gallery Thumbnail
                galleryThumbnailButton

                // Capture Button
                captureButton

                // Flash Toggle
                flashToggleButton
            }

            // Zoom Slider
            if captureMode == .photo || captureMode == .video {
                zoomControl
            }
        }
        .padding(.horizontal, 20)
    }

    private var captureModeSelector: some View {
        HStack(spacing: 24) {
            ForEach(CaptureMode.allCases, id: \.self) { mode in
                Button(action: {
                    withAnimation(.spring()) {
                        captureMode = mode
                        cameraManager.setCaptureMode(mode)
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.title3)
                        Text(mode.displayName)
                            .font(.caption2)
                    }
                    .foregroundColor(captureMode == mode ? .white : .white.opacity(0.5))
                    .scaleEffect(captureMode == mode ? 1.1 : 1.0)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var galleryThumbnailButton: some View {
        Button(action: { showingGallery = true }) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .frame(width: 50, height: 50)

                Image(systemName: "photo.stack.fill")
                    .font(.title3)
                    .foregroundColor(.white)

                if recentCaptureCount > 0 {
                    VStack {
                        HStack {
                            Spacer()
                            Circle()
                                .fill(Color.red)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Text("\(recentCaptureCount)")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                )
                        }
                        Spacer()
                    }
                    .frame(width: 50, height: 50)
                }
            }
        }
    }

    private var captureButton: some View {
        Button(action: handleCapture) {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 5)
                    .frame(width: 75, height: 75)

                Circle()
                    .fill(isCapturing ? Color.red : Color.white)
                    .frame(width: 60, height: 60)
                    .scaleEffect(isCapturing ? 0.8 : 1.0)
            }
        }
        .disabled(isCapturing)
        .animation(.spring(response: 0.3), value: isCapturing)
    }

    private var flashToggleButton: some View {
        Button(action: {
            withAnimation {
                flashMode = flashMode.next()
                cameraManager.setFlashMode(flashMode)
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: flashMode.icon)
                    .font(.title2)
                    .foregroundColor(.white)

                Text(flashMode.displayName)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(width: 50, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
        }
    }

    private var zoomControl: some View {
        VStack(spacing: 8) {
            HStack {
                Text("1×")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))

                Slider(value: $zoomLevel, in: 1...5, step: 0.1) { _ in
                    cameraManager.setZoom(zoomLevel)
                }
                .tint(.white)

                Text("5×")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }

            Text(String(format: "%.1f×", zoomLevel))
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Camera Setup & Control
    private func setupCamera() {
        Task {
            do {
                try await cameraManager.setupCamera()
                print("✅ Camera setup complete")
            } catch {
                print("❌ Camera setup failed: \(error)")
            }
        }
    }

    private func startAIDetection() {
        Task {
            // Simulate AI detection updates
            for try await objects in aiOverlay.detectionStream() {
                detectedObjects = objects
                updateAISuggestion(for: objects)
            }
        }
    }

    private func updateAISuggestion(for objects: [DetectedObject]) {
        guard !objects.isEmpty else {
            aiSuggestion = nil
            return
        }

        // Generate contextual suggestions
        let suggestions = [
            "Perfect lighting for portraits detected",
            "Try getting closer to the subject",
            "Great composition - capture now!",
            "Multiple faces detected - group photo mode?",
            "Beautiful landscape - use wide angle"
        ]

        withAnimation(.spring()) {
            aiSuggestion = suggestions.randomElement()
        }

        // Auto-dismiss after 5 seconds
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            withAnimation(.spring()) {
                aiSuggestion = nil
            }
        }
    }

    // MARK: - Gesture Handlers
    private func handlePinchZoom(_ value: CGFloat) {
        let newZoom = max(1.0, min(5.0, zoomLevel * value))
        zoomLevel = newZoom
        cameraManager.setZoom(newZoom)
    }

    private func handleSwipeGesture(_ value: DragGesture.Value) {
        let horizontalMovement = value.translation.width
        let verticalMovement = value.translation.height

        if abs(horizontalMovement) > abs(verticalMovement) {
            // Horizontal swipe - change mode
            if horizontalMovement > 50 {
                cycleMode(forward: false)
            } else if horizontalMovement < -50 {
                cycleMode(forward: true)
            }
        } else {
            // Vertical swipe - adjust exposure
            let exposureAdjustment = Float(verticalMovement / 100)
            cameraManager.adjustExposure(exposureAdjustment)
        }
    }

    private func handleDoubleTap() {
        // Toggle between front and back camera
        cameraManager.switchCamera()
    }

    private func handleSingleTap() {
        // Auto-focus (handled by camera manager)
    }

    private func cycleMode(forward: Bool) {
        let modes = CaptureMode.allCases
        guard let currentIndex = modes.firstIndex(of: captureMode) else { return }

        let newIndex: Int
        if forward {
            newIndex = (currentIndex + 1) % modes.count
        } else {
            newIndex = (currentIndex - 1 + modes.count) % modes.count
        }

        withAnimation(.spring()) {
            captureMode = modes[newIndex]
            cameraManager.setCaptureMode(captureMode)
        }
    }

    // MARK: - Capture Handler
    private func handleCapture() {
        guard !isCapturing else { return }

        isCapturing = true

        // Show capture animation
        withAnimation(.easeOut(duration: 0.1)) {
            showCaptureAnimation = true
        }

        Task {
            do {
                switch captureMode {
                case .photo:
                    try await cameraManager.capturePhoto()
                case .video:
                    if cameraManager.isRecording {
                        try await cameraManager.stopRecording()
                    } else {
                        try await cameraManager.startRecording()
                    }
                case .ocr:
                    try await cameraManager.captureForOCR()
                case .ar:
                    try await cameraManager.captureAR()
                }

                // Update capture count
                recentCaptureCount += 1

                // Hide animation
                try? await Task.sleep(nanoseconds: 100_000_000)
                withAnimation(.easeIn(duration: 0.1)) {
                    showCaptureAnimation = false
                }

            } catch {
                print("❌ Capture failed: \(error)")
            }

            isCapturing = false
        }
    }
}

// MARK: - Camera Preview Layer
struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Update if needed
    }

    class PreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

// MARK: - AI Detection Overlay View
struct AIDetectionOverlayView: View {
    let detectedObjects: [DetectedObject]
    let frameSize: CGSize

    var body: some View {
        ZStack {
            ForEach(detectedObjects) { object in
                DetectionBoxView(object: object, frameSize: frameSize)
            }
        }
    }
}

struct DetectionBoxView: View {
    let object: DetectedObject
    let frameSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            let box = convertBoundingBox(object.boundingBox, in: frameSize)

            Rectangle()
                .stroke(object.color, lineWidth: 3)
                .frame(width: box.width, height: box.height)
                .position(x: box.midX, y: box.midY)
                .overlay(
                    VStack(alignment: .leading, spacing: 4) {
                        Text(object.label)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Text("\(object.confidencePercent)%")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(object.color.opacity(0.8))
                    )
                    .position(x: box.minX + 40, y: box.minY - 15)
                )
        }
    }

    private func convertBoundingBox(_ box: CGRect, in size: CGSize) -> CGRect {
        // Convert normalized coordinates to screen coordinates
        CGRect(
            x: box.origin.x * size.width,
            y: box.origin.y * size.height,
            width: box.width * size.width,
            height: box.height * size.height
        )
    }
}

// MARK: - Focus Indicator View
struct FocusIndicatorView: View {
    let point: CGPoint
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.yellow, lineWidth: 2)
                .frame(width: 80, height: 80)

            Circle()
                .stroke(Color.yellow, lineWidth: 1)
                .frame(width: 60, height: 60)
        }
        .position(point)
        .opacity(animate ? 0 : 1)
        .scaleEffect(animate ? 1.2 : 1.0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                animate = true
            }
        }
    }
}

// MARK: - Gesture Indicator View
struct GestureIndicatorView: View {
    let icon: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundColor(.white)

            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
        }
        .padding(20)
    }
}

// MARK: - Supporting Types
enum CaptureMode: String, CaseIterable {
    case photo, video, ocr, ar

    var displayName: String {
        switch self {
        case .photo: return "Photo"
        case .video: return "Video"
        case .ocr: return "OCR"
        case .ar: return "AR"
        }
    }

    var icon: String {
        switch self {
        case .photo: return "camera.fill"
        case .video: return "video.fill"
        case .ocr: return "doc.text.viewfinder"
        case .ar: return "arkit"
        }
    }
}

enum FlashMode: String {
    case auto, on, off

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .on: return "On"
        case .off: return "Off"
        }
    }

    var icon: String {
        switch self {
        case .auto: return "bolt.badge.automatic.fill"
        case .on: return "bolt.fill"
        case .off: return "bolt.slash.fill"
        }
    }

    func next() -> FlashMode {
        switch self {
        case .auto: return .on
        case .on: return .off
        case .off: return .auto
        }
    }
}

struct DetectedObject: Identifiable {
    let id = UUID()
    let label: String
    let confidence: Float
    let boundingBox: CGRect

    var confidencePercent: Int {
        Int(confidence * 100)
    }

    var color: Color {
        Color(hue: Double(label.hash % 360) / 360.0, saturation: 0.8, brightness: 0.9)
    }
}

enum CameraGesture {
    case pinch, swipeLeft, swipeRight, swipeUp, swipeDown, doubleTap, none

    var icon: String {
        switch self {
        case .pinch: return "arrow.up.left.and.arrow.down.right"
        case .swipeLeft: return "arrow.left"
        case .swipeRight: return "arrow.right"
        case .swipeUp: return "arrow.up"
        case .swipeDown: return "arrow.down"
        case .doubleTap: return "hand.tap.fill"
        case .none: return ""
        }
    }

    var displayName: String {
        switch self {
        case .pinch: return "Zoom"
        case .swipeLeft: return "Previous Mode"
        case .swipeRight: return "Next Mode"
        case .swipeUp: return "Brighten"
        case .swipeDown: return "Darken"
        case .doubleTap: return "Switch Camera"
        case .none: return ""
        }
    }
}

// MARK: - Supporting Classes
@MainActor
class AdvancedCameraManager: ObservableObject {
    @Published var captureSession = AVCaptureSession()
    @Published var focusPoint: CGPoint?
    @Published var isRecording = false

    func setupCamera() async throws {
        // Camera setup implementation
    }

    func setCaptureMode(_ mode: CaptureMode) {
        // Mode switching implementation
    }

    func setFlashMode(_ mode: FlashMode) {
        // Flash mode implementation
    }

    func setZoom(_ level: CGFloat) {
        // Zoom implementation
    }

    func adjustExposure(_ value: Float) {
        // Exposure adjustment
    }

    func switchCamera() {
        // Camera switching
    }

    func stopSession() {
        captureSession.stopRunning()
    }

    func capturePhoto() async throws {
        // Photo capture implementation
    }

    func startRecording() async throws {
        isRecording = true
    }

    func stopRecording() async throws {
        isRecording = false
    }

    func captureForOCR() async throws {
        // OCR capture implementation
    }

    func captureAR() async throws {
        // AR capture implementation
    }
}

@MainActor
class CameraGestureRecognizer: ObservableObject {
    @Published var currentGesture: CameraGesture = .none
    @Published var isActive = false
}

@MainActor
class AIOverlayManager: ObservableObject {
    func detectionStream() -> AsyncStream<[DetectedObject]> {
        AsyncStream { continuation in
            // Simulate real-time detection
            Task {
                while true {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    let objects = generateMockDetections()
                    continuation.yield(objects)
                }
            }
        }
    }

    private func generateMockDetections() -> [DetectedObject] {
        // Mock detection for demo
        return []
    }
}

// MARK: - Camera Settings View
struct CameraSettingsView: View {
    @ObservedObject var cameraManager: AdvancedCameraManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Quality") {
                    Picker("Resolution", selection: .constant("4K")) {
                        Text("720p").tag("720p")
                        Text("1080p").tag("1080p")
                        Text("4K").tag("4K")
                    }
                }

                Section("AI Features") {
                    Toggle("Real-time Object Detection", isOn: .constant(true))
                    Toggle("AI Suggestions", isOn: .constant(true))
                    Toggle("Face Recognition", isOn: .constant(false))
                }
            }
            .navigationTitle("Camera Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
