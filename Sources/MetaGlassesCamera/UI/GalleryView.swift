import SwiftUI
import Photos

/// Beautiful Photo Gallery with Smart Organization
@MainActor
public struct GalleryView: View {

    // MARK: - State
    @State private var photos: [GalleryPhoto] = []
    @State private var selectedFilter: FilterType = .all
    @State private var searchText = ""
    @State private var selectedPhoto: GalleryPhoto?
    @State private var showingDetail = false

    // MARK: - Body
    public var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Search and filters
                searchAndFilterSection

                // Photo grid
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 2),
                        GridItem(.flexible(), spacing: 2),
                        GridItem(.flexible(), spacing: 2)
                    ], spacing: 2) {
                        ForEach(filteredPhotos) { photo in
                            PhotoGridItem(photo: photo)
                                .onTapGesture {
                                    selectedPhoto = photo
                                    showingDetail = true
                                }
                        }
                    }
                }
            }
        }
        .navigationTitle("Gallery")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingDetail) {
            if let photo = selectedPhoto {
                PhotoDetailView(photo: photo)
            }
        }
        .onAppear {
            loadPhotos()
        }
    }

    // MARK: - Search and Filter Section
    private var searchAndFilterSection: some View {
        VStack(spacing: 12) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.6))

                TextField("Search photos...", text: $searchText)
                    .foregroundColor(.white)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal)

            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(FilterType.allCases, id: \.self) { filter in
                        FilterChip(
                            title: filter.title,
                            icon: filter.icon,
                            isSelected: selectedFilter == filter
                        ) {
                            withAnimation(.spring()) {
                                selectedFilter = filter
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }

    // MARK: - Computed Properties
    private var filteredPhotos: [GalleryPhoto] {
        var filtered = photos

        // Apply filter
        switch selectedFilter {
        case .all:
            break
        case .people:
            filtered = filtered.filter { !$0.recognizedPeople.isEmpty }
        case .places:
            filtered = filtered.filter { $0.location != nil }
        case .favorites:
            filtered = filtered.filter { $0.isFavorite }
        case .recent:
            filtered = Array(filtered.prefix(50))
        }

        // Apply search
        if !searchText.isEmpty {
            filtered = filtered.filter { photo in
                photo.recognizedPeople.contains { $0.localizedCaseInsensitiveContains(searchText) } ||
                photo.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }

        return filtered
    }

    // MARK: - Data Loading
    private func loadPhotos() {
        // In production, load from Core Data or CloudKit
        // For now, create sample data
        photos = []
    }
}

// MARK: - Photo Grid Item
struct PhotoGridItem: View {
    let photo: GalleryPhoto

    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.1))
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                // In production, load actual thumbnail
                Image(systemName: "photo.fill")
                    .font(.largeTitle)
                    .foregroundColor(.white.opacity(0.3))
            )
            .overlay(
                // VIP badge
                VStack {
                    HStack {
                        if !photo.recognizedPeople.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "person.fill")
                                    .font(.caption2)
                                Text("\(photo.recognizedPeople.count)")
                                    .font(.caption2)
                            }
                            .foregroundColor(.white)
                            .padding(6)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                            )
                            .padding(8)
                        }

                        Spacer()

                        if photo.isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(8)
                        }
                    }

                    Spacer()
                }
            )
    }
}

// MARK: - Filter Chip
struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(isSelected ? Color(hex: "667eea") : .white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? .white : .white.opacity(0.2))
            )
        }
    }
}

// MARK: - Filter Type
enum FilterType: CaseIterable {
    case all, people, places, favorites, recent

    var title: String {
        switch self {
        case .all: return "All"
        case .people: return "People"
        case .places: return "Places"
        case .favorites: return "Favorites"
        case .recent: return "Recent"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .people: return "person.2"
        case .places: return "map"
        case .favorites: return "heart"
        case .recent: return "clock"
        }
    }
}

// MARK: - Gallery Photo Model
struct GalleryPhoto: Identifiable {
    let id = UUID()
    let timestamp: Date
    let recognizedPeople: [String]
    let location: String?
    let tags: [String]
    let isFavorite: Bool
}

// MARK: - Preview
struct GalleryView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            GalleryView()
        }
    }
}
