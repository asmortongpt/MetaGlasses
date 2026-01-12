import SwiftUI
import Photos
import Vision

/// Smart Gallery View with AI-powered organization, clustering, and natural language search
/// Beautiful photo management with intelligent categorization
@MainActor
public struct SmartGalleryView: View {

    // MARK: - State Management
    @StateObject private var galleryManager = SmartGalleryManager()
    @StateObject private var aiSearchEngine = AISearchEngine()

    @State private var viewMode: GalleryViewMode = .grid
    @State private var groupingMode: GroupingMode = .date
    @State private var searchText = ""
    @State private var selectedPhoto: GalleryPhoto?
    @State private var showingPhotoDetail = false
    @State private var showingComparison = false
    @State private var comparisonPhotos: [GalleryPhoto] = []
    @State private var isSelectionMode = false
    @State private var selectedPhotos: Set<UUID> = []
    @State private var showingFilterOptions = false

    @Environment(\.dismiss) var dismiss

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 2)
    ]

    // MARK: - Body
    public var body: some View {
        NavigationStack {
            ZStack {
                // Background
                backgroundGradient

                VStack(spacing: 0) {
                    // Search Bar
                    searchBar
                        .padding()

                    // View Controls
                    controlsBar
                        .padding(.horizontal)

                    // Main Content
                    mainContentArea
                }
            }
            .navigationTitle("Smart Gallery")
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
                        Button(action: { isSelectionMode.toggle() }) {
                            Label(isSelectionMode ? "Cancel Selection" : "Select Photos", systemImage: "checkmark.circle")
                        }

                        Divider()

                        Button(action: { showingComparison = true }) {
                            Label("Compare Photos", systemImage: "photo.on.rectangle.angled")
                        }

                        Button(action: exportSelected) {
                            Label("Export Selected", systemImage: "square.and.arrow.up")
                        }

                        Divider()

                        Button(action: { showingFilterOptions = true }) {
                            Label("Advanced Filters", systemImage: "line.3.horizontal.decrease.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.white)
                    }
                }
            }
            .sheet(isPresented: $showingPhotoDetail) {
                if let photo = selectedPhoto {
                    PhotoDetailEnhancedView(photo: photo, galleryManager: galleryManager)
                }
            }
            .sheet(isPresented: $showingComparison) {
                PhotoComparisonView(photos: comparisonPhotos)
            }
            .sheet(isPresented: $showingFilterOptions) {
                AdvancedFiltersView(manager: galleryManager)
            }
            .onAppear {
                loadGallery()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Background
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.black,
                Color(hex: "1a1a2e").opacity(0.8),
                Color.black
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Search Bar
    private var searchBar: some View {
        HStack(spacing: 12) {
            // Natural Language Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.6))

                TextField("Search with natural language...", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .onChange(of: searchText) { newValue in
                        performSmartSearch(query: newValue)
                    }

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.1))
            )

            // Voice Search Button
            Button(action: startVoiceSearch) {
                Image(systemName: "mic.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                    )
            }
        }
    }

    // MARK: - Controls Bar
    private var controlsBar: some View {
        VStack(spacing: 12) {
            // View Mode Selector
            HStack(spacing: 16) {
                ForEach(GalleryViewMode.allCases, id: \.self) { mode in
                    Button(action: {
                        withAnimation(.spring()) {
                            viewMode = mode
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: mode.icon)
                                .font(.callout)
                            Text(mode.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(viewMode == mode ? .white : .white.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(viewMode == mode ? .white.opacity(0.2) : .clear)
                        )
                    }
                }

                Spacer()
            }

            // Grouping Mode Selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(GroupingMode.allCases, id: \.self) { mode in
                        groupingChip(mode)
                    }
                }
            }
        }
    }

    private func groupingChip(_ mode: GroupingMode) -> some View {
        Button(action: {
            withAnimation(.spring()) {
                groupingMode = mode
                galleryManager.regroupPhotos(by: mode)
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.caption)
                Text(mode.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .foregroundColor(groupingMode == mode ? .white : .white.opacity(0.6))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(groupingMode == mode ? .blue.opacity(0.5) : .white.opacity(0.1))
            )
        }
    }

    // MARK: - Main Content Area
    @ViewBuilder
    private var mainContentArea: some View {
        switch viewMode {
        case .grid:
            gridView
        case .list:
            listView
        case .cluster:
            clusterView
        case .map:
            mapView
        }
    }

    // MARK: - Grid View
    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(galleryManager.filteredPhotos) { photo in
                    PhotoGridCell(
                        photo: photo,
                        isSelected: selectedPhotos.contains(photo.id),
                        isSelectionMode: isSelectionMode
                    )
                    .onTapGesture {
                        handlePhotoTap(photo)
                    }
                    .onLongPressGesture {
                        handlePhotoLongPress(photo)
                    }
                }
            }
            .padding(2)
        }
    }

    // MARK: - List View
    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(galleryManager.groupedPhotos) { group in
                    photoGroupSection(group)
                }
            }
            .padding()
        }
    }

    private func photoGroupSection(_ group: PhotoGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Group Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text(group.subtitle)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()

                Text("\(group.photos.count)")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))
            }

            // Photos in Group
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(group.photos) { photo in
                        PhotoListCell(photo: photo)
                            .onTapGesture {
                                selectedPhoto = photo
                                showingPhotoDetail = true
                            }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.05))
        )
    }

    // MARK: - Cluster View
    private var clusterView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                ForEach(galleryManager.clusters) { cluster in
                    PhotoClusterCard(cluster: cluster)
                        .onTapGesture {
                            // Show cluster details
                            galleryManager.showCluster(cluster)
                        }
                }
            }
            .padding()
        }
    }

    // MARK: - Map View
    private var mapView: some View {
        VStack {
            Text("Map View")
                .font(.title)
                .foregroundColor(.white)

            Text("Photos organized by location")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))

            // TODO: Integrate MapKit to show photo locations
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Photo Interaction Handlers
    private func handlePhotoTap(_ photo: GalleryPhoto) {
        if isSelectionMode {
            if selectedPhotos.contains(photo.id) {
                selectedPhotos.remove(photo.id)
            } else {
                selectedPhotos.insert(photo.id)
            }
        } else {
            selectedPhoto = photo
            showingPhotoDetail = true
        }
    }

    private func handlePhotoLongPress(_ photo: GalleryPhoto) {
        if !isSelectionMode {
            isSelectionMode = true
            selectedPhotos.insert(photo.id)
        }
    }

    // MARK: - Search & Actions
    private func performSmartSearch(query: String) {
        Task {
            await aiSearchEngine.search(query: query, in: galleryManager.allPhotos)
            galleryManager.applySearchResults(aiSearchEngine.results)
        }
    }

    private func startVoiceSearch() {
        print("🎤 Starting voice search...")
        // Implement voice search
    }

    private func exportSelected() {
        print("📤 Exporting \(selectedPhotos.count) photos...")
    }

    private func loadGallery() {
        Task {
            await galleryManager.loadPhotos()
        }
    }
}

// MARK: - Photo Grid Cell
struct PhotoGridCell: View {
    let photo: GalleryPhoto
    let isSelected: Bool
    let isSelectionMode: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Photo Thumbnail
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .aspectRatio(1, contentMode: .fill)
                .overlay(
                    Group {
                        if let thumbnail = photo.thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "photo.fill")
                                .font(.largeTitle)
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                )
                .clipped()

            // AI Tag Badge
            if !photo.aiTags.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                    Text("\(photo.aiTags.count)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(4)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                )
                .padding(4)
                .opacity(isSelectionMode ? 0 : 1)
            }

            // Selection Indicator
            if isSelectionMode {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundColor(isSelected ? .blue : .white)
                            .padding(8)
                    }
                    Spacer()
                }
            }
        }
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
        )
    }
}

// MARK: - Photo List Cell
struct PhotoListCell: View {
    let photo: GalleryPhoto

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 150, height: 150)
                .overlay(
                    Group {
                        if let thumbnail = photo.thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                    }
                )
                .clipped()
                .cornerRadius(12)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(photo.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))

                if !photo.recognizedPeople.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                        Text(photo.recognizedPeople.joined(separator: ", "))
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .frame(width: 150)
    }
}

// MARK: - Photo Cluster Card
struct PhotoClusterCard: View {
    let cluster: PhotoCluster

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Cluster Preview (mosaic of photos)
            GeometryReader { geometry in
                ZStack {
                    ForEach(Array(cluster.representativePhotos.prefix(4).enumerated()), id: \.offset) { index, photo in
                        if let thumbnail = photo.thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(
                                    width: geometry.size.width / 2 - 2,
                                    height: geometry.size.height / 2 - 2
                                )
                                .clipped()
                                .offset(
                                    x: index % 2 == 0 ? 0 : geometry.size.width / 2 + 2,
                                    y: index < 2 ? 0 : geometry.size.height / 2 + 2
                                )
                        }
                    }
                }
            }
            .aspectRatio(1, contentMode: .fill)
            .cornerRadius(12)

            // Cluster Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: cluster.icon)
                        .font(.caption)
                        .foregroundColor(cluster.color)

                    Text(cluster.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    Spacer()
                }

                Text("\(cluster.photoCount) photos")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.05))
        )
    }
}

// MARK: - Photo Detail Enhanced View
struct PhotoDetailEnhancedView: View {
    let photo: GalleryPhoto
    @ObservedObject var galleryManager: SmartGalleryManager
    @Environment(\.dismiss) var dismiss

    @State private var currentZoom = 1.0
    @State private var showingMetadata = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Photo Display
                    if let image = photo.fullImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(currentZoom)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        currentZoom = value
                                    }
                            )
                    }

                    // Info Panel
                    VStack(alignment: .leading, spacing: 16) {
                        // AI Analysis
                        if !photo.aiDescription.isEmpty {
                            aiAnalysisSection
                        }

                        // People Recognized
                        if !photo.recognizedPeople.isEmpty {
                            recognizedPeopleSection
                        }

                        // Location
                        if let location = photo.location {
                            locationSection(location)
                        }

                        // AI Tags
                        if !photo.aiTags.isEmpty {
                            aiTagsSection
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .padding()
                }
            }
            .navigationTitle("Photo Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showingMetadata = true }) {
                            Label("View Metadata", systemImage: "info.circle")
                        }
                        Button(action: sharePhoto) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        Button(action: deletePhoto) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingMetadata) {
                PhotoMetadataView(photo: photo)
            }
        }
    }

    private var aiAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.yellow)
                Text("AI Analysis")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            Text(photo.aiDescription)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
        }
    }

    private var recognizedPeopleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundColor(.blue)
                Text("People")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(photo.recognizedPeople, id: \.self) { person in
                        PersonChip(name: person)
                    }
                }
            }
        }
    }

    private func locationSection(_ location: String) -> some View {
        HStack {
            Image(systemName: "mappin.circle.fill")
                .foregroundColor(.green)
            Text(location)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
        }
    }

    private var aiTagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.headline)
                .foregroundColor(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(photo.aiTags, id: \.self) { tag in
                        TagChip(tag: tag)
                    }
                }
            }
        }
    }

    private func sharePhoto() {
        print("📤 Sharing photo...")
    }

    private func deletePhoto() {
        print("🗑️ Deleting photo...")
    }
}

// MARK: - Photo Comparison View
struct PhotoComparisonView: View {
    let photos: [GalleryPhoto]
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(photos.prefix(4)) { photo in
                        if let image = photo.fullImage {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .cornerRadius(12)

                                Text(photo.timestamp.formatted())
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("Compare Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Advanced Filters View
struct AdvancedFiltersView: View {
    @ObservedObject var manager: SmartGalleryManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Date Range") {
                    DatePicker("From", selection: .constant(Date()), displayedComponents: .date)
                    DatePicker("To", selection: .constant(Date()), displayedComponents: .date)
                }

                Section("Content") {
                    Toggle("Has People", isOn: .constant(false))
                    Toggle("Has Location", isOn: .constant(false))
                    Toggle("AI Tagged", isOn: .constant(true))
                }

                Section("Quality") {
                    Picker("Minimum Quality", selection: .constant("Any")) {
                        Text("Any").tag("Any")
                        Text("Good").tag("Good")
                        Text("Excellent").tag("Excellent")
                    }
                }
            }
            .navigationTitle("Advanced Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Photo Metadata View
struct PhotoMetadataView: View {
    let photo: GalleryPhoto
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("Basic Info") {
                    metadataRow(label: "Date", value: photo.timestamp.formatted())
                    metadataRow(label: "Size", value: "\(photo.fileSize / 1024) KB")
                }

                if !photo.aiTags.isEmpty {
                    Section("AI Tags") {
                        ForEach(photo.aiTags, id: \.self) { tag in
                            Text(tag)
                        }
                    }
                }
            }
            .navigationTitle("Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
}

// MARK: - Helper Views
struct PersonChip: View {
    let name: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.blue)
                .frame(width: 24, height: 24)
                .overlay(
                    Text(String(name.prefix(1)))
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                )

            Text(name)
                .font(.subheadline)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.blue.opacity(0.2))
        )
    }
}

struct TagChip: View {
    let tag: String

    var body: some View {
        Text(tag)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(.white.opacity(0.2))
            )
            .foregroundColor(.white)
    }
}

// MARK: - Supporting Types
enum GalleryViewMode: String, CaseIterable {
    case grid, list, cluster, map

    var displayName: String {
        switch self {
        case .grid: return "Grid"
        case .list: return "List"
        case .cluster: return "Clusters"
        case .map: return "Map"
        }
    }

    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        case .cluster: return "square.stack.3d.up.fill"
        case .map: return "map"
        }
    }
}

enum GroupingMode: String, CaseIterable {
    case date, location, people, events, aiTags

    var displayName: String {
        switch self {
        case .date: return "Date"
        case .location: return "Location"
        case .people: return "People"
        case .events: return "Events"
        case .aiTags: return "AI Tags"
        }
    }

    var icon: String {
        switch self {
        case .date: return "calendar"
        case .location: return "mappin.circle"
        case .people: return "person.2"
        case .events: return "star"
        case .aiTags: return "sparkles"
        }
    }
}

struct GalleryPhoto: Identifiable {
    let id: UUID
    let timestamp: Date
    let thumbnail: UIImage?
    let fullImage: UIImage?
    let recognizedPeople: [String]
    let aiTags: [String]
    let aiDescription: String
    let location: String?
    let fileSize: Int
}

struct PhotoGroup: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let photos: [GalleryPhoto]
}

struct PhotoCluster: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let color: Color
    let photoCount: Int
    let representativePhotos: [GalleryPhoto]
}

// MARK: - Managers
@MainActor
class SmartGalleryManager: ObservableObject {
    @Published var allPhotos: [GalleryPhoto] = []
    @Published var filteredPhotos: [GalleryPhoto] = []
    @Published var groupedPhotos: [PhotoGroup] = []
    @Published var clusters: [PhotoCluster] = []

    func loadPhotos() async {
        // Simulate loading photos
        try? await Task.sleep(nanoseconds: 500_000_000)

        // In production, this would load from photo library
        allPhotos = []
        filteredPhotos = allPhotos
    }

    func regroupPhotos(by mode: GroupingMode) {
        // Regroup photos based on selected mode
        print("📊 Regrouping photos by \(mode.displayName)")
    }

    func applySearchResults(_ results: [GalleryPhoto]) {
        filteredPhotos = results
    }

    func showCluster(_ cluster: PhotoCluster) {
        print("📁 Showing cluster: \(cluster.title)")
    }
}

@MainActor
class AISearchEngine: ObservableObject {
    @Published var results: [GalleryPhoto] = []

    func search(query: String, in photos: [GalleryPhoto]) async {
        // AI-powered natural language search
        print("🔍 Searching: \(query)")
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
