import SwiftUI

/// Interactive Onboarding & Tutorial System
/// Beautiful first-time user experience with feature discovery
@MainActor
public struct OnboardingTutorial: View {

    @StateObject private var onboardingManager = OnboardingManager()
    @State private var currentStep = 0
    @State private var showPermissionRequest = false
    @State private var permissionType: PermissionType?

    @Environment(\.dismiss) var dismiss
    @Binding var hasCompletedOnboarding: Bool

    public init(hasCompletedOnboarding: Binding<Bool>) {
        self._hasCompletedOnboarding = hasCompletedOnboarding
    }

    private let totalSteps = 5

    public var body: some View {
        ZStack {
            // Animated Background
            animatedBackground

            VStack(spacing: 0) {
                // Progress Bar
                progressBar

                // Main Content
                TabView(selection: $currentStep) {
                    ForEach(0..<totalSteps, id: \.self) { step in
                        stepView(for: step)
                            .tag(step)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(), value: currentStep)

                // Navigation Buttons
                navigationButtons
                    .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPermissionRequest) {
            if let permission = permissionType {
                PermissionRequestView(permissionType: permission) {
                    showPermissionRequest = false
                    nextStep()
                }
            }
        }
    }

    // MARK: - Animated Background
    private var animatedBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "667eea"),
                    Color(hex: "764ba2"),
                    Color(hex: "f093fb")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Floating particles
            ForEach(0..<20, id: \.self) { _ in
                Circle()
                    .fill(.white.opacity(0.1))
                    .frame(width: CGFloat.random(in: 20...80))
                    .position(
                        x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                        y: CGFloat.random(in: 0...UIScreen.main.bounds.height)
                    )
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Progress Bar
    private var progressBar: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.white.opacity(0.2))
                        .frame(height: 4)

                    Rectangle()
                        .fill(.white)
                        .frame(
                            width: geometry.size.width * CGFloat(currentStep + 1) / CGFloat(totalSteps),
                            height: 4
                        )
                        .animation(.spring(), value: currentStep)
                }
            }
            .frame(height: 4)

            Text("Step \(currentStep + 1) of \(totalSteps)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding()
    }

    // MARK: - Step Views
    @ViewBuilder
    private func stepView(for step: Int) -> some View {
        switch step {
        case 0:
            welcomeStep
        case 1:
            featuresStep
        case 2:
            aiPowerStep
        case 3:
            privacyStep
        case 4:
            readyStep
        default:
            EmptyView()
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 30) {
            Spacer()

            // App Icon/Logo
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 120, height: 120)
                .overlay(
                    Image(systemName: "eye.fill")
                        .font(.system(size: 60))
                        .foregroundColor(Color(hex: "667eea"))
                )
                .shadow(color: .black.opacity(0.3), radius: 20, y: 10)

            Text("Welcome to MetaGlasses")
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text("Your AI-powered reality companion that remembers everything and helps you see more")
                .font(.title3)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    private var featuresStep: some View {
        VStack(spacing: 40) {
            Text("Powerful Features")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)

            VStack(spacing: 24) {
                featureRow(
                    icon: "camera.viewfinder",
                    title: "Smart Camera",
                    description: "AI-powered camera with real-time object detection and suggestions"
                )

                featureRow(
                    icon: "person.fill.viewfinder",
                    title: "Face Recognition",
                    description: "Never forget a face - recognize VIPs instantly"
                )

                featureRow(
                    icon: "doc.text.viewfinder",
                    title: "Advanced OCR",
                    description: "Extract text from any image with industry-leading accuracy"
                )

                featureRow(
                    icon: "brain.head.profile",
                    title: "AI Memory",
                    description: "Remember everything with intelligent context and recall"
                )
            }
            .padding(.horizontal, 30)

            Spacer()
        }
        .padding(.top, 40)
    }

    private var aiPowerStep: some View {
        VStack(spacing: 30) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.yellow, .orange, .pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .yellow.opacity(0.5), radius: 20)

            Text("AI-Powered Intelligence")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)

            VStack(spacing: 16) {
                Text("MetaGlasses uses advanced AI to:")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.9))

                aiCapabilityItem("Understand context and provide smart suggestions")
                aiCapabilityItem("Learn your patterns and preferences")
                aiCapabilityItem("Build a knowledge graph of your life")
                aiCapabilityItem("Help you find memories instantly")
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    private var privacyStep: some View {
        VStack(spacing: 30) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
                .shadow(color: .green.opacity(0.5), radius: 20)

            Text("Your Privacy Matters")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 20) {
                privacyPoint(
                    icon: "iphone.lock",
                    title: "On-Device Processing",
                    description: "Most AI runs locally on your device"
                )

                privacyPoint(
                    icon: "key.fill",
                    title: "Encrypted Storage",
                    description: "All your data is encrypted at rest"
                )

                privacyPoint(
                    icon: "hand.raised.fill",
                    title: "You Control Your Data",
                    description: "Export or delete your data anytime"
                )
            }
            .padding(.horizontal, 30)

            Spacer()

            Button(action: {
                permissionType = .camera
                showPermissionRequest = true
            }) {
                Text("Grant Permissions")
                    .font(.headline)
                    .foregroundColor(Color(hex: "667eea"))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.white)
                    )
            }
            .padding(.horizontal, 30)
        }
    }

    private var readyStep: some View {
        VStack(spacing: 30) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 100))
                .foregroundColor(.green)
                .shadow(color: .green.opacity(0.5), radius: 20)

            Text("You're All Set!")
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(.white)

            Text("MetaGlasses is ready to help you see more and remember everything")
                .font(.title3)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Quick Start Checklist
            VStack(alignment: .leading, spacing: 16) {
                quickStartItem("Take your first photo", completed: false)
                quickStartItem("Add a VIP contact", completed: false)
                quickStartItem("Try the AI assistant", completed: false)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.1))
            )
            .padding(.horizontal, 30)

            Spacer()
        }
    }

    // MARK: - Helper Views
    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(
                    Circle()
                        .fill(.white.opacity(0.2))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }

            Spacer()
        }
    }

    private func aiCapabilityItem(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)

            Text(text)
                .font(.body)
                .foregroundColor(.white.opacity(0.9))
        }
    }

    private func privacyPoint(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.green)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }

    private func quickStartItem(_ text: String, completed: Bool) -> some View {
        HStack {
            Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                .foregroundColor(completed ? .green : .white.opacity(0.5))

            Text(text)
                .font(.subheadline)
                .foregroundColor(.white)

            Spacer()
        }
    }

    // MARK: - Navigation Buttons
    private var navigationButtons: some View {
        HStack(spacing: 20) {
            if currentStep > 0 {
                Button(action: previousStep) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.white.opacity(0.2))
                    )
                }
            }

            Button(action: {
                if currentStep == totalSteps - 1 {
                    completeOnboarding()
                } else {
                    nextStep()
                }
            }) {
                HStack {
                    Text(currentStep == totalSteps - 1 ? "Get Started" : "Continue")
                    Image(systemName: "chevron.right")
                }
                .font(.headline)
                .foregroundColor(Color(hex: "667eea"))
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white)
                )
            }
        }
        .padding(.horizontal, 30)
    }

    // MARK: - Actions
    private func nextStep() {
        withAnimation(.spring()) {
            if currentStep < totalSteps - 1 {
                currentStep += 1
            }
        }
    }

    private func previousStep() {
        withAnimation(.spring()) {
            if currentStep > 0 {
                currentStep -= 1
            }
        }
    }

    private func completeOnboarding() {
        onboardingManager.markCompleted()
        hasCompletedOnboarding = true
        dismiss()
    }
}

// MARK: - Permission Request View
struct PermissionRequestView: View {
    let permissionType: PermissionType
    let onComplete: () -> Void

    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()

                Image(systemName: permissionType.icon)
                    .font(.system(size: 80))
                    .foregroundColor(permissionType.color)

                Text(permissionType.title)
                    .font(.title)
                    .fontWeight(.bold)

                Text(permissionType.description)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 40)

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(permissionType.reasons, id: \.self) { reason in
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(reason)
                                .font(.subheadline)
                        }
                    }
                }
                .padding()

                Spacer()

                VStack(spacing: 16) {
                    Button(action: {
                        requestPermission()
                    }) {
                        Text("Allow Access")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(permissionType.color)
                            )
                    }

                    Button(action: {
                        dismiss()
                    }) {
                        Text("Not Now")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func requestPermission() {
        // Request actual permission
        Task {
            await permissionType.request()
            onComplete()
        }
    }
}

// MARK: - Supporting Types
enum PermissionType {
    case camera, photos, location, microphone

    var title: String {
        switch self {
        case .camera: return "Camera Access"
        case .photos: return "Photo Library Access"
        case .location: return "Location Access"
        case .microphone: return "Microphone Access"
        }
    }

    var icon: String {
        switch self {
        case .camera: return "camera.fill"
        case .photos: return "photo.fill"
        case .location: return "location.fill"
        case .microphone: return "mic.fill"
        }
    }

    var color: Color {
        switch self {
        case .camera: return .blue
        case .photos: return .purple
        case .location: return .green
        case .microphone: return .red
        }
    }

    var description: String {
        switch self {
        case .camera: return "MetaGlasses needs camera access to capture photos and analyze your environment in real-time"
        case .photos: return "Access your photos to organize them with AI and build your visual memory"
        case .location: return "Add location context to your memories and photos automatically"
        case .microphone: return "Use voice commands and transcribe speech for better accessibility"
        }
    }

    var reasons: [String] {
        switch self {
        case .camera:
            return [
                "Take photos and videos",
                "Real-time AI object detection",
                "Face recognition features"
            ]
        case .photos:
            return [
                "Smart photo organization",
                "AI-powered search",
                "Backup and sync"
            ]
        case .location:
            return [
                "Automatic location tagging",
                "Place-based memories",
                "Contextual suggestions"
            ]
        case .microphone:
            return [
                "Voice commands",
                "Voice notes",
                "Accessibility features"
            ]
        }
    }

    func request() async {
        // Request permission implementation
        print("🔐 Requesting \(title)...")
    }
}

@MainActor
class OnboardingManager: ObservableObject {
    @Published var isCompleted = false

    func markCompleted() {
        isCompleted = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
