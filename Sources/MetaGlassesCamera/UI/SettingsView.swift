import SwiftUI

/// Comprehensive Settings View
@MainActor
public struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @AppStorage("darkMode") private var darkMode = false
    @AppStorage("autoCapture") private var autoCapture = false
    @AppStorage("notifyOnVIP") private var notifyOnVIP = true
    @AppStorage("videoQuality") private var videoQuality = VideoQuality.ultra4K.rawValue
    @AppStorage("photoFormat") private var photoFormat = PhotoFormat.heic.rawValue

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                List {
                    // Camera Settings
                    Section {
                        Picker("Video Quality", selection: $videoQuality) {
                            ForEach(VideoQuality.allCases, id: \.rawValue) { quality in
                                Text(quality.displayName).tag(quality.rawValue)
                            }
                        }

                        Picker("Photo Format", selection: $photoFormat) {
                            ForEach(PhotoFormat.allCases, id: \.rawValue) { format in
                                Text(format.displayName).tag(format.rawValue)
                            }
                        }

                        Toggle("Auto-Capture Moments", isOn: $autoCapture)
                    } header: {
                        Text("Camera")
                    }

                    // AI Settings
                    Section {
                        Toggle("VIP Notifications", isOn: $notifyOnVIP)

                        NavigationLink("Manage VIPs") {
                            VIPManagerView()
                        }
                    } header: {
                        Text("AI Features")
                    }

                    // Appearance
                    Section {
                        Toggle("Dark Mode", isOn: $darkMode)
                    } header: {
                        Text("Appearance")
                    }

                    // About
                    Section {
                        HStack {
                            Text("Version")
                            Spacer()
                            Text("1.0.0")
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Text("About")
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}

enum VideoQuality: String, CaseIterable {
    case hd720p, hd1080p, ultra4K

    var displayName: String {
        switch self {
        case .hd720p: return "HD 720p"
        case .hd1080p: return "HD 1080p"
        case .ultra4K: return "4K Ultra HD"
        }
    }
}

enum PhotoFormat: String, CaseIterable {
    case heic, jpeg, raw

    var displayName: String {
        switch self {
        case .heic: return "HEIC (Efficient)"
        case .jpeg: return "JPEG (Compatible)"
        case .raw: return "RAW (Professional)"
        }
    }
}
