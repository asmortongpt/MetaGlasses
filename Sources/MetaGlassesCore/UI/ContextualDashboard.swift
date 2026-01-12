import SwiftUI
import Combine

/// Contextual Dashboard - Real-time context display with AI suggestions
/// Shows what's happening now and provides intelligent recommendations
@MainActor
public struct ContextualDashboard: View {

    // MARK: - State Management
    @StateObject private var contextEngine = ContextEngine()
    @StateObject private var patternAnalyzer = PatternAnalyzer()
    @StateObject private var suggestionEngine = SuggestionEngine()

    @State private var currentContext: ContextState = .idle
    @State private var activeSuggestions: [SmartSuggestion] = []
    @State private var recentPatterns: [RecognizedPattern] = []
    @State private var showingPatternDetail: RecognizedPattern?
    @State private var expandedSections: Set<DashboardSection> = [.currentContext]

    @Environment(\.dismiss) var dismiss

    // MARK: - Body
    public var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient

                ScrollView {
                    LazyVStack(spacing: 20) {
                        // Current Context Card
                        currentContextCard

                        // Active Suggestions
                        if !activeSuggestions.isEmpty {
                            suggestionsSection
                        }

                        // Pattern Insights
                        patternInsightsSection

                        // Daily Summary
                        dailySummarySection

                        // Quick Actions
                        quickActionsSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: refreshDashboard) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        Button(action: exportSummary) {
                            Label("Export Summary", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.white)
                    }
                }
            }
            .sheet(item: $showingPatternDetail) { pattern in
                PatternDetailView(pattern: pattern)
            }
            .onAppear {
                startContextMonitoring()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Background
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(hex: "1a1a2e"),
                Color(hex: "16213e"),
                Color(hex: "0f3460")
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Current Context Card
    private var currentContextCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: currentContext.icon)
                    .font(.title)
                    .foregroundStyle(currentContext.gradient)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Context")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))

                    Text(currentContext.displayName)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }

                Spacer()

                // Live Indicator
                if currentContext != .idle {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                            .shadow(color: .green, radius: 4)

                        Text("LIVE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                }
            }

            Divider()
                .background(Color.white.opacity(0.2))

            // Context Details
            contextDetailsGrid

            // Context Description
            Text(currentContext.description)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(3)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
        )
    }

    private var contextDetailsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            contextMetric(icon: "location.fill", label: "Location", value: contextEngine.currentLocation)
            contextMetric(icon: "clock.fill", label: "Time", value: contextEngine.currentTime)
            contextMetric(icon: "person.2.fill", label: "People", value: "\(contextEngine.nearbyPeople)")
        }
    }

    private func contextMetric(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)

            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
    }

    // MARK: - Suggestions Section
    private var suggestionsSection: some View {
        collapsibleSection(
            title: "Smart Suggestions",
            icon: "lightbulb.fill",
            section: .suggestions
        ) {
            VStack(spacing: 12) {
                ForEach(activeSuggestions.prefix(3)) { suggestion in
                    SuggestionCard(suggestion: suggestion)
                        .onTapGesture {
                            executeSuggestion(suggestion)
                        }
                }
            }
        }
    }

    // MARK: - Pattern Insights Section
    private var patternInsightsSection: some View {
        collapsibleSection(
            title: "Pattern Insights",
            icon: "chart.line.uptrend.xyaxis",
            section: .patterns
        ) {
            VStack(spacing: 12) {
                ForEach(recentPatterns.prefix(5)) { pattern in
                    PatternInsightCard(pattern: pattern)
                        .onTapGesture {
                            showingPatternDetail = pattern
                        }
                }

                if recentPatterns.isEmpty {
                    Text("No patterns detected yet")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.vertical, 20)
                }
            }
        }
    }

    // MARK: - Daily Summary Section
    private var dailySummarySection: some View {
        collapsibleSection(
            title: "Today's Summary",
            icon: "calendar.circle.fill",
            section: .summary
        ) {
            VStack(spacing: 16) {
                // Stats Grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    summaryStatCard(
                        icon: "camera.fill",
                        value: "\(contextEngine.todayStats.photoCaptured)",
                        label: "Photos",
                        color: .blue
                    )

                    summaryStatCard(
                        icon: "person.2.fill",
                        value: "\(contextEngine.todayStats.peopleRecognized)",
                        label: "People",
                        color: .purple
                    )

                    summaryStatCard(
                        icon: "mappin.circle.fill",
                        value: "\(contextEngine.todayStats.placesVisited)",
                        label: "Places",
                        color: .green
                    )

                    summaryStatCard(
                        icon: "brain.head.profile",
                        value: "\(contextEngine.todayStats.aiInsights)",
                        label: "AI Insights",
                        color: .orange
                    )
                }

                // Timeline Preview
                HStack {
                    Text("Activity Timeline")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    Spacer()

                    Button(action: { /* Show full timeline */ }) {
                        Text("View All")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }

                activityTimeline
            }
        }
    }

    private func summaryStatCard(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.05))
        )
    }

    private var activityTimeline: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(contextEngine.todayActivities) { activity in
                    TimelineActivityView(activity: activity)
                }
            }
        }
    }

    // MARK: - Quick Actions Section
    private var quickActionsSection: some View {
        collapsibleSection(
            title: "Quick Actions",
            icon: "bolt.circle.fill",
            section: .actions
        ) {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                quickActionButton(
                    icon: "camera.viewfinder",
                    title: "Quick Capture",
                    gradient: [.blue, .purple]
                ) {
                    // Quick capture action
                }

                quickActionButton(
                    icon: "person.fill.viewfinder",
                    title: "Scan VIP",
                    gradient: [.purple, .pink]
                ) {
                    // Scan VIP action
                }

                quickActionButton(
                    icon: "doc.text.viewfinder",
                    title: "Scan Text",
                    gradient: [.green, .mint]
                ) {
                    // OCR action
                }

                quickActionButton(
                    icon: "brain",
                    title: "AI Analyze",
                    gradient: [.orange, .red]
                ) {
                    // AI analysis action
                }
            }
        }
    }

    private func quickActionButton(icon: String, title: String, gradient: [Color], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: gradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )

                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.05))
            )
        }
    }

    // MARK: - Collapsible Section Helper
    private func collapsibleSection<Content: View>(
        title: String,
        icon: String,
        section: DashboardSection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: {
                withAnimation(.spring()) {
                    if expandedSections.contains(section) {
                        expandedSections.remove(section)
                    } else {
                        expandedSections.insert(section)
                    }
                }
            }) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(.blue)
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)

                    Spacer()

                    Image(systemName: expandedSections.contains(section) ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            if expandedSections.contains(section) {
                content()
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Actions
    private func startContextMonitoring() {
        Task {
            // Start real-time context monitoring
            for await context in contextEngine.contextStream() {
                currentContext = context
                activeSuggestions = await suggestionEngine.generateSuggestions(for: context)
                recentPatterns = await patternAnalyzer.analyzePatterns()
            }
        }
    }

    private func executeSuggestion(_ suggestion: SmartSuggestion) {
        print("✨ Executing suggestion: \(suggestion.title)")
    }

    private func refreshDashboard() {
        Task {
            await contextEngine.refresh()
        }
    }

    private func exportSummary() {
        print("📤 Exporting daily summary...")
    }
}

// MARK: - Supporting Views
struct SuggestionCard: View {
    let suggestion: SmartSuggestion

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: suggestion.icon)
                .font(.title3)
                .foregroundColor(suggestion.color)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(suggestion.color.opacity(0.2))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text(suggestion.description)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.white.opacity(0.4))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.05))
        )
    }
}

struct PatternInsightCard: View {
    let pattern: RecognizedPattern

    var body: some View {
        HStack(spacing: 12) {
            // Pattern Icon with Badge
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(pattern.color.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: pattern.icon)
                            .font(.title3)
                            .foregroundColor(pattern.color)
                    )

                // Confidence Badge
                Text("\(pattern.confidencePercent)%")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(4)
                    .background(
                        Circle()
                            .fill(Color.green)
                    )
                    .offset(x: 5, y: -5)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(pattern.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text(pattern.description)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)

                Text("Detected \(pattern.occurrences) times")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.05))
        )
    }
}

struct TimelineActivityView: View {
    let activity: DailyActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(activity.color)
                    .frame(width: 12, height: 12)

                Text(activity.time)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }

            Text(activity.title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(2)
        }
        .frame(width: 120)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.05))
        )
    }
}

struct PatternDetailView: View {
    let pattern: RecognizedPattern
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Pattern Overview
                    VStack(spacing: 16) {
                        Circle()
                            .fill(pattern.color)
                            .frame(width: 100, height: 100)
                            .overlay(
                                Image(systemName: pattern.icon)
                                    .font(.system(size: 40))
                                    .foregroundColor(.white)
                            )

                        Text(pattern.title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Text(pattern.description)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()

                    // Statistics
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Statistics")
                            .font(.headline)
                            .foregroundColor(.white)

                        detailRow(label: "Occurrences", value: "\(pattern.occurrences)")
                        detailRow(label: "Confidence", value: "\(pattern.confidencePercent)%")
                        detailRow(label: "First Detected", value: pattern.firstDetected.formatted())
                        detailRow(label: "Last Detected", value: pattern.lastDetected.formatted())
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.white.opacity(0.05))
                    )
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("Pattern Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
    }
}

// MARK: - Supporting Types
enum DashboardSection: Hashable {
    case currentContext, suggestions, patterns, summary, actions
}

enum ContextState {
    case idle, working, commuting, socializing, exercising, eating, traveling

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .working: return "At Work"
        case .commuting: return "Commuting"
        case .socializing: return "Socializing"
        case .exercising: return "Exercising"
        case .eating: return "Having a Meal"
        case .traveling: return "Traveling"
        }
    }

    var icon: String {
        switch self {
        case .idle: return "moon.zzz.fill"
        case .working: return "briefcase.fill"
        case .commuting: return "car.fill"
        case .socializing: return "person.3.fill"
        case .exercising: return "figure.run"
        case .eating: return "fork.knife"
        case .traveling: return "airplane"
        }
    }

    var description: String {
        switch self {
        case .idle: return "No active context detected"
        case .working: return "You appear to be in a work environment"
        case .commuting: return "You're on the move"
        case .socializing: return "Social gathering detected"
        case .exercising: return "Physical activity in progress"
        case .eating: return "Meal time detected"
        case .traveling: return "Travel mode active"
        }
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: [color1, color2],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var color1: Color {
        switch self {
        case .idle: return .purple
        case .working: return .blue
        case .commuting: return .orange
        case .socializing: return .pink
        case .exercising: return .green
        case .eating: return .red
        case .traveling: return .cyan
        }
    }

    private var color2: Color {
        switch self {
        case .idle: return .blue
        case .working: return .cyan
        case .commuting: return .yellow
        case .socializing: return .purple
        case .exercising: return .mint
        case .eating: return .orange
        case .traveling: return .blue
        }
    }
}

struct SmartSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String
    let color: Color
    let actionType: SuggestionAction
}

enum SuggestionAction {
    case capture, remember, navigate, contact
}

struct RecognizedPattern: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String
    let color: Color
    let confidence: Float
    let occurrences: Int
    let firstDetected: Date
    let lastDetected: Date

    var confidencePercent: Int {
        Int(confidence * 100)
    }
}

struct DailyStats {
    var photoCaptured: Int = 0
    var peopleRecognized: Int = 0
    var placesVisited: Int = 0
    var aiInsights: Int = 0
}

struct DailyActivity: Identifiable {
    let id = UUID()
    let time: String
    let title: String
    let color: Color
}

// MARK: - Managers
@MainActor
class ContextEngine: ObservableObject {
    @Published var currentLocation: String = "Unknown"
    @Published var currentTime: String = Date().formatted(date: .omitted, time: .shortened)
    @Published var nearbyPeople: Int = 0
    @Published var todayStats = DailyStats()
    @Published var todayActivities: [DailyActivity] = []

    func contextStream() -> AsyncStream<ContextState> {
        AsyncStream { continuation in
            Task {
                // Simulate context updates
                continuation.yield(.idle)
                while true {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    continuation.yield(.working)
                }
            }
        }
    }

    func refresh() async {
        // Refresh context data
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
}

@MainActor
class PatternAnalyzer: ObservableObject {
    func analyzePatterns() async -> [RecognizedPattern] {
        // Analyze user patterns
        return []
    }
}

@MainActor
class SuggestionEngine: ObservableObject {
    func generateSuggestions(for context: ContextState) async -> [SmartSuggestion] {
        // Generate contextual suggestions
        return []
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
