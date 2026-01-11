import SwiftUI

/// Stunning Modern Home View with Glassmorphism
/// The main dashboard for MetaGlasses - billion times better UI
@MainActor
public struct ModernHomeView: View {

    // MARK: - State
    @State private var selectedTab: Tab = .capture
    @State private var showSettings = false
    @State private var showVIPManager = false
    @State private var recentPhotos: [CapturedPhoto] = []
    @State private var aiSuggestion: String? = nil

    // MARK: - Body
    public var body: some View {
        NavigationStack {
            ZStack {
                // Dynamic gradient background
                LinearGradient(
                    colors: [
                        Color(hex: "667eea"),
                        Color(hex: "764ba2"),
                        Color(hex: "f093fb"),
                        Color(hex: "4facfe")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                // Main content
                ScrollView {
                    VStack(spacing: 24) {
                        // Header with glassmorphism
                        headerSection

                        // AI Suggestion Card
                        if let suggestion = aiSuggestion {
                            aiSuggestionCard(suggestion)
                        }

                        // Quick Actions
                        quickActionsGrid

                        // Recent Captures
                        recentCapturesSection

                        // Stats Overview
                        statsSection
                    }
                    .padding()
                }

                // Floating Action Button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        captureButton
                            .padding(32)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.white)
                            .font(.title3)
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showVIPManager = true
                    } label: {
                        Image(systemName: "person.2.fill")
                            .foregroundColor(.white)
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showVIPManager) {
                VIPManagerView()
            }
            .onAppear {
                loadData()
            }
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        GlassmorphicCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MetaGlasses")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)

                        Text("Your AI-Powered Reality")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }

                    Spacer()

                    // Connection status
                    connectionBadge
                }

                // Time and location
                HStack {
                    Image(systemName: "location.fill")
                        .font(.caption)
                    Text("Current Location")
                        .font(.caption)

                    Spacer()

                    Text(Date().formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                }
                .foregroundColor(.white.opacity(0.7))
            }
            .padding()
        }
    }

    private var connectionBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .shadow(color: .green, radius: 4)

            Text("Connected")
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - AI Suggestion Card
    private func aiSuggestionCard(_ suggestion: String) -> some View {
        GlassmorphicCard {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundColor(.yellow)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(.white.opacity(0.2))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Suggestion")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.8))

                    Text(suggestion)
                        .font(.subheadline)
                        .foregroundColor(.white)
                }

                Spacer()

                Button {
                    // Dismiss suggestion
                    withAnimation(.spring()) {
                        aiSuggestion = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Quick Actions Grid
    private var quickActionsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            QuickActionCard(
                icon: "camera.fill",
                title: "Capture",
                subtitle: "Take photo",
                gradient: [Color.blue, Color.purple]
            ) {
                // Capture action
            }

            QuickActionCard(
                icon: "video.fill",
                title: "Record",
                subtitle: "4K Video",
                gradient: [Color.red, Color.orange]
            ) {
                // Record action
            }

            QuickActionCard(
                icon: "doc.text.viewfinder",
                title: "Scan Text",
                subtitle: "OCR",
                gradient: [Color.green, Color.mint]
            ) {
                // OCR action
            }

            QuickActionCard(
                icon: "hand.raised.fill",
                title: "Gestures",
                subtitle: "Control",
                gradient: [Color.purple, Color.pink]
            ) {
                // Gesture action
            }
        }
    }

    // MARK: - Recent Captures Section
    private var recentCapturesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Captures")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Spacer()

                NavigationLink {
                    GalleryView()
                } label: {
                    Text("View All")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recentPhotos.prefix(5), id: \.id) { photo in
                        RecentPhotoCard(photo: photo)
                    }
                }
            }
        }
    }

    // MARK: - Stats Section
    private var statsSection: some View {
        GlassmorphicCard {
            VStack(spacing: 20) {
                Text("Today's Activity")
                    .font(.headline)
                    .foregroundColor(.white)

                HStack(spacing: 20) {
                    StatItem(icon: "camera", value: "24", label: "Photos")
                    StatItem(icon: "video", value: "5", label: "Videos")
                    StatItem(icon: "person.2", value: "8", label: "VIPs Seen")
                }
            }
            .padding()
        }
    }

    // MARK: - Capture Button
    private var captureButton: some View {
        Button {
            // Capture action
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.white.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 70, height: 70)
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)

                Image(systemName: "camera.fill")
                    .font(.system(size: 30))
                    .foregroundColor(Color(hex: "667eea"))
            }
        }
        .scaleEffect(1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: true)
    }

    // MARK: - Data Loading
    private func loadData() {
        // Load recent photos and AI suggestions
        aiSuggestion = "Perfect lighting for portraits!"
        // In production, load actual data
    }
}

// MARK: - Quick Action Card
struct QuickActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let gradient: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassmorphicCard {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 32))
                        .foregroundColor(.white)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                            .foregroundColor(.white)

                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recent Photo Card
struct RecentPhotoCard: View {
    let photo: CapturedPhoto

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Photo thumbnail
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.1))
                .frame(width: 150, height: 150)
                .overlay(
                    Image(systemName: "photo.fill")
                        .font(.largeTitle)
                        .foregroundColor(.white.opacity(0.3))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(photo.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))

                if !photo.recognizedPeople.isEmpty {
                    Text(photo.recognizedPeople.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Stat Item
struct StatItem: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)

            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Glassmorphic Card
struct GlassmorphicCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
            )
    }
}

// MARK: - Supporting Types
enum Tab {
    case capture, gallery, vip, settings
}

struct CapturedPhoto: Identifiable {
    let id = UUID()
    let timestamp: Date
    let recognizedPeople: [String]
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Preview
struct ModernHomeView_Previews: PreviewProvider {
    static var previews: some View {
        ModernHomeView()
    }
}
