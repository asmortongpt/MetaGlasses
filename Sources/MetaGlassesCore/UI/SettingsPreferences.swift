import SwiftUI

/// Comprehensive Settings & Preferences
/// Beautiful settings interface with privacy controls, AI model selection, and data management
@MainActor
public struct SettingsPreferences: View {

    @StateObject private var settingsManager = SettingsManager()
    @State private var showingDataManagement = false
    @State private var showingAbout = false
    @State private var showingExport = false
    @State private var showingDeleteConfirmation = false

    @Environment(\.dismiss) var dismiss

    public var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient

                Form {
                    // Profile Section
                    profileSection

                    // AI & Intelligence
                    aiSection

                    // Privacy & Security
                    privacySection

                    // Camera & Capture
                    cameraSection

                    // Display & Appearance
                    displaySection

                    // Data Management
                    dataSection

                    // About
                    aboutSection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }
            }
            .sheet(isPresented: $showingDataManagement) {
                DataManagementView(manager: settingsManager)
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
            .sheet(isPresented: $showingExport) {
                DataExportView()
            }
            .alert("Delete All Data", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    settingsManager.deleteAllData()
                }
            } message: {
                Text("This will permanently delete all your data, photos, and memories. This action cannot be undone.")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Background
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(hex: "1a1a2e"),
                Color(hex: "16213e")
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Profile Section
    private var profileSection: some View {
        Section {
            HStack(spacing: 16) {
                // Profile Picture
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.title)
                            .foregroundColor(.white)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(settingsManager.userName)
                        .font(.headline)
                        .foregroundColor(.white)

                    Text(settingsManager.userEmail)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))

                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Premium Active")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }

                Spacer()

                Button(action: {}) {
                    Text("Edit")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.white.opacity(0.05))
    }

    // MARK: - AI Section
    private var aiSection: some View {
        Section {
            // AI Model Selection
            Picker("AI Model", selection: $settingsManager.selectedAIModel) {
                ForEach(AIModel.allCases, id: \.self) { model in
                    Text(model.displayName).tag(model)
                }
            }

            // AI Features
            Toggle("Real-time Object Detection", isOn: $settingsManager.enableObjectDetection)
            Toggle("Face Recognition", isOn: $settingsManager.enableFaceRecognition)
            Toggle("OCR Text Extraction", isOn: $settingsManager.enableOCR)
            Toggle("AI Suggestions", isOn: $settingsManager.enableAISuggestions)

            // Processing Location
            Picker("Processing", selection: $settingsManager.aiProcessingLocation) {
                Text("On-Device").tag(AIProcessingLocation.onDevice)
                Text("Cloud").tag(AIProcessingLocation.cloud)
                Text("Hybrid").tag(AIProcessingLocation.hybrid)
            }

        } header: {
            Text("AI & Intelligence")
        } footer: {
            Text("On-device processing keeps your data private but may be slower. Cloud processing is faster but requires internet.")
        }
        .listRowBackground(Color.white.opacity(0.05))
    }

    // MARK: - Privacy Section
    private var privacySection: some View {
        Section {
            Toggle("Face Data Encryption", isOn: $settingsManager.encryptFaceData)
            Toggle("Location Tracking", isOn: $settingsManager.enableLocationTracking)
            Toggle("Usage Analytics", isOn: $settingsManager.shareAnalytics)
            Toggle("Crash Reports", isOn: $settingsManager.shareCrashReports)

            NavigationLink {
                PermissionsManagementView()
            } label: {
                HStack {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.green)
                    Text("Manage Permissions")
                        .foregroundColor(.white)
                }
            }

            NavigationLink {
                PrivacyPolicyView()
            } label: {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundColor(.blue)
                    Text("Privacy Policy")
                        .foregroundColor(.white)
                }
            }

        } header: {
            Text("Privacy & Security")
        } footer: {
            Text("Your privacy is our priority. All sensitive data is encrypted.")
        }
        .listRowBackground(Color.white.opacity(0.05))
    }

    // MARK: - Camera Section
    private var cameraSection: some View {
        Section {
            Picker("Photo Quality", selection: $settingsManager.photoQuality) {
                Text("High").tag(PhotoQuality.high)
                Text("Medium").tag(PhotoQuality.medium)
                Text("Low").tag(PhotoQuality.low)
            }

            Picker("Video Quality", selection: $settingsManager.videoQuality) {
                Text("4K").tag(VideoQuality.fourK)
                Text("1080p").tag(VideoQuality.fullHD)
                Text("720p").tag(VideoQuality.hd)
            }

            Toggle("Grid Lines", isOn: $settingsManager.showGridLines)
            Toggle("Live Photo", isOn: $settingsManager.enableLivePhoto)
            Toggle("Auto Night Mode", isOn: $settingsManager.autoNightMode)
            Toggle("Capture Sound", isOn: $settingsManager.enableCaptureSound)

        } header: {
            Text("Camera & Capture")
        }
        .listRowBackground(Color.white.opacity(0.05))
    }

    // MARK: - Display Section
    private var displaySection: some View {
        Section {
            Picker("Theme", selection: $settingsManager.theme) {
                Text("System").tag(AppTheme.system)
                Text("Light").tag(AppTheme.light)
                Text("Dark").tag(AppTheme.dark)
            }

            Toggle("Haptic Feedback", isOn: $settingsManager.enableHaptics)
            Toggle("Sound Effects", isOn: $settingsManager.enableSoundEffects)
            Toggle("Animations", isOn: $settingsManager.enableAnimations)

            Picker("Language", selection: $settingsManager.selectedLanguage) {
                Text("English").tag("en")
                Text("Spanish").tag("es")
                Text("French").tag("fr")
                Text("German").tag("de")
            }

        } header: {
            Text("Display & Appearance")
        }
        .listRowBackground(Color.white.opacity(0.05))
    }

    // MARK: - Data Section
    private var dataSection: some View {
        Section {
            // Storage Info
            HStack {
                Image(systemName: "internaldrive.fill")
                    .foregroundColor(.blue)
                Text("Storage Used")
                    .foregroundColor(.white)
                Spacer()
                Text(settingsManager.storageUsed)
                    .foregroundColor(.white.opacity(0.7))
            }

            // Data Management
            Button(action: { showingDataManagement = true }) {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.orange)
                    Text("Manage Data")
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            // Export Data
            Button(action: { showingExport = true }) {
                HStack {
                    Image(systemName: "square.and.arrow.up.fill")
                        .foregroundColor(.green)
                    Text("Export All Data")
                        .foregroundColor(.white)
                }
            }

            // Clear Cache
            Button(action: settingsManager.clearCache) {
                HStack {
                    Image(systemName: "trash.fill")
                        .foregroundColor(.yellow)
                    Text("Clear Cache")
                        .foregroundColor(.white)
                    Spacer()
                    Text(settingsManager.cacheSize)
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            // Delete All Data
            Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Delete All Data")
                }
            }

        } header: {
            Text("Data Management")
        } footer: {
            Text("Manage your local data, export to other services, or delete everything.")
        }
        .listRowBackground(Color.white.opacity(0.05))
    }

    // MARK: - About Section
    private var aboutSection: some View {
        Section {
            Button(action: { showingAbout = true }) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("About MetaGlasses")
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            HStack {
                Text("Version")
                    .foregroundColor(.white)
                Spacer()
                Text(settingsManager.appVersion)
                    .foregroundColor(.white.opacity(0.7))
            }

            Button(action: settingsManager.checkForUpdates) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.green)
                    Text("Check for Updates")
                        .foregroundColor(.white)
                }
            }

            NavigationLink {
                SupportView()
            } label: {
                HStack {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundColor(.purple)
                    Text("Help & Support")
                        .foregroundColor(.white)
                }
            }

            NavigationLink {
                LicensesView()
            } label: {
                HStack {
                    Image(systemName: "doc.plaintext.fill")
                        .foregroundColor(.gray)
                    Text("Open Source Licenses")
                        .foregroundColor(.white)
                }
            }

        } header: {
            Text("About")
        }
        .listRowBackground(Color.white.opacity(0.05))
    }
}

// MARK: - Data Management View
struct DataManagementView: View {
    @ObservedObject var manager: SettingsManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Storage Breakdown") {
                    storageItem(label: "Photos", size: "2.3 GB", icon: "photo.fill", color: .blue)
                    storageItem(label: "Videos", size: "1.5 GB", icon: "video.fill", color: .purple)
                    storageItem(label: "Face Data", size: "150 MB", icon: "person.fill", color: .orange)
                    storageItem(label: "Knowledge Graph", size: "50 MB", icon: "brain", color: .green)
                    storageItem(label: "Cache", size: "200 MB", icon: "doc.fill", color: .gray)
                }

                Section("Actions") {
                    Button("Optimize Storage") {
                        manager.optimizeStorage()
                    }

                    Button("Download Data") {
                        // Download all data
                    }
                }
            }
            .navigationTitle("Data Management")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func storageItem(label: String, size: String, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 30)
            Text(label)
            Spacer()
            Text(size)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Permissions Management View
struct PermissionsManagementView: View {
    var body: some View {
        Form {
            Section {
                permissionRow(
                    title: "Camera",
                    icon: "camera.fill",
                    status: "Allowed",
                    color: .green
                )

                permissionRow(
                    title: "Photos",
                    icon: "photo.fill",
                    status: "Allowed",
                    color: .green
                )

                permissionRow(
                    title: "Location",
                    icon: "location.fill",
                    status: "While Using",
                    color: .orange
                )

                permissionRow(
                    title: "Microphone",
                    icon: "mic.fill",
                    status: "Denied",
                    color: .red
                )
            }

            Section {
                Button("Open System Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
        .navigationTitle("Permissions")
    }

    private func permissionRow(title: String, icon: String, status: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 30)
            Text(title)
            Spacer()
            Text(status)
                .font(.subheadline)
                .foregroundColor(color)
        }
    }
}

// MARK: - About View
struct AboutView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 30) {
                    // App Icon
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .overlay(
                            Image(systemName: "eye.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.white)
                        )
                        .shadow(radius: 10)

                    Text("MetaGlasses")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Version 1.0.0")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("Your AI-powered reality companion that helps you remember everything and see more of the world around you.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 40)

                    VStack(spacing: 12) {
                        aboutRow(icon: "envelope.fill", text: "Contact Support")
                        aboutRow(icon: "star.fill", text: "Rate on App Store")
                        aboutRow(icon: "square.and.arrow.up.fill", text: "Share with Friends")
                    }
                    .padding()
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func aboutRow(icon: String, text: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 30)
            Text(text)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }
}

// MARK: - Other Support Views
struct DataExportView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Export Format") {
                    Toggle("Include Photos", isOn: .constant(true))
                    Toggle("Include Videos", isOn: .constant(true))
                    Toggle("Include Face Data", isOn: .constant(false))
                    Toggle("Include Knowledge Graph", isOn: .constant(true))
                }

                Section {
                    Button("Export as ZIP") {
                        // Export logic
                    }

                    Button("Share via AirDrop") {
                        // AirDrop logic
                    }
                }
            }
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            Text("Privacy Policy content would go here...")
                .padding()
        }
        .navigationTitle("Privacy Policy")
    }
}

struct SupportView: View {
    var body: some View {
        Form {
            Section("Get Help") {
                Button("FAQ") { }
                Button("Contact Support") { }
                Button("Report a Bug") { }
                Button("Request a Feature") { }
            }
        }
        .navigationTitle("Help & Support")
    }
}

struct LicensesView: View {
    var body: some View {
        List {
            Text("Open source licenses would be listed here...")
        }
        .navigationTitle("Open Source Licenses")
    }
}

// MARK: - Supporting Types
enum AIModel: String, CaseIterable {
    case gpt4, claude, gemini, local

    var displayName: String {
        switch self {
        case .gpt4: return "GPT-4"
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        case .local: return "On-Device Model"
        }
    }
}

enum AIProcessingLocation: String {
    case onDevice, cloud, hybrid
}

enum PhotoQuality: String {
    case high, medium, low
}

enum VideoQuality: String {
    case fourK = "4K"
    case fullHD = "1080p"
    case hd = "720p"
}

enum AppTheme: String {
    case system, light, dark
}

// MARK: - Settings Manager
@MainActor
class SettingsManager: ObservableObject {
    @Published var userName = "User"
    @Published var userEmail = "user@example.com"

    @Published var selectedAIModel: AIModel = .gpt4
    @Published var enableObjectDetection = true
    @Published var enableFaceRecognition = true
    @Published var enableOCR = true
    @Published var enableAISuggestions = true
    @Published var aiProcessingLocation: AIProcessingLocation = .hybrid

    @Published var encryptFaceData = true
    @Published var enableLocationTracking = true
    @Published var shareAnalytics = false
    @Published var shareCrashReports = true

    @Published var photoQuality: PhotoQuality = .high
    @Published var videoQuality: VideoQuality = .fullHD
    @Published var showGridLines = true
    @Published var enableLivePhoto = false
    @Published var autoNightMode = true
    @Published var enableCaptureSound = true

    @Published var theme: AppTheme = .system
    @Published var enableHaptics = true
    @Published var enableSoundEffects = true
    @Published var enableAnimations = true
    @Published var selectedLanguage = "en"

    var storageUsed: String { "4.2 GB" }
    var cacheSize: String { "200 MB" }
    var appVersion: String { "1.0.0" }

    func clearCache() {
        print("🗑️ Clearing cache...")
    }

    func deleteAllData() {
        print("⚠️ Deleting all data...")
    }

    func optimizeStorage() {
        print("🔧 Optimizing storage...")
    }

    func checkForUpdates() {
        print("🔄 Checking for updates...")
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
