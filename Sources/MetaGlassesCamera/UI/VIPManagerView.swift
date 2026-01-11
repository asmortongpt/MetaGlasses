import SwiftUI

/// VIP People Management - Learn and recognize your family and friends
@MainActor
public struct VIPManagerView: View {

    // MARK: - State
    @State private var vips: [VIPEntry] = []
    @State private var showingAddVIP = false
    @State private var selectedVIP: VIPEntry?
    @Environment(\.dismiss) private var dismiss

    // MARK: - Body
    public var body: some View {
        NavigationStack {
            ZStack {
                // Background
                LinearGradient(
                    colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Header card
                        headerCard

                        // VIP List
                        if vips.isEmpty {
                            emptyStateView
                        } else {
                            vipListSection
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("VIP Recognition")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddVIP = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .sheet(isPresented: $showingAddVIP) {
                AddVIPView { newVIP in
                    vips.append(newVIP)
                }
            }
            .sheet(item: $selectedVIP) { vip in
                VIPDetailView(vip: vip)
            }
            .onAppear {
                loadVIPs()
            }
        }
    }

    // MARK: - Header Card
    private var headerCard: some View {
        GlassmorphicCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "person.2.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(vips.count) VIPs")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Text("Auto-recognized in photos")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }

                    Spacer()
                }

                Divider()
                    .background(.white.opacity(0.2))

                HStack(spacing: 20) {
                    StatBadge(icon: "camera", value: "\(totalPhotos)", label: "Photos")
                    StatBadge(icon: "eye", value: "\(totalSightings)", label: "Sightings")
                }
            }
            .padding()
        }
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        GlassmorphicCard {
            VStack(spacing: 20) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 80))
                    .foregroundColor(.white.opacity(0.4))

                VStack(spacing: 8) {
                    Text("No VIPs Yet")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("Add family and friends to auto-recognize them in photos")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    showingAddVIP = true
                } label: {
                    Text("Add First VIP")
                        .fontWeight(.semibold)
                        .foregroundColor(Color(hex: "667eea"))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(.white)
                        )
                }
            }
            .padding(40)
        }
    }

    // MARK: - VIP List Section
    private var vipListSection: some View {
        LazyVStack(spacing: 12) {
            ForEach(vips) { vip in
                VIPCard(vip: vip) {
                    selectedVIP = vip
                }
            }
        }
    }

    // MARK: - Computed Properties
    private var totalPhotos: Int {
        vips.reduce(0) { $0 + $1.photoCount }
    }

    private var totalSightings: Int {
        vips.reduce(0) { $0 + $1.sightingCount }
    }

    // MARK: - Data Loading
    private func loadVIPs() {
        // In production, load from PersonalAI
        // For now, sample data
        vips = []
    }
}

// MARK: - VIP Card
struct VIPCard: View {
    let vip: VIPEntry
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassmorphicCard {
                HStack(spacing: 16) {
                    // Profile photo
                    Circle()
                        .fill(.white.opacity(0.2))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.title)
                                .foregroundColor(.white.opacity(0.5))
                        )

                    // VIP Info
                    VStack(alignment: .leading, spacing: 6) {
                        Text(vip.name)
                            .font(.headline)
                            .foregroundColor(.white)

                        Text(vip.relationship)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))

                        HStack(spacing: 16) {
                            Label("\(vip.photoCount)", systemImage: "camera.fill")
                                .font(.caption)
                            Label("Last seen \(vip.lastSeen.formatted(.relative(presentation: .named)))", systemImage: "clock.fill")
                                .font(.caption)
                        }
                        .foregroundColor(.white.opacity(0.6))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding()
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add VIP View
struct AddVIPView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var relationship = ""
    @State private var selectedRelationship: RelationshipType = .family
    let onSave: (VIPEntry) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Photo capture
                        Button {
                            // Capture photo
                        } label: {
                            Circle()
                                .fill(.white.opacity(0.2))
                                .frame(width: 150, height: 150)
                                .overlay(
                                    VStack(spacing: 8) {
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 40))
                                        Text("Take Photo")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.white)
                                )
                        }

                        // Name field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name")
                                .font(.headline)
                                .foregroundColor(.white)

                            TextField("Enter name", text: $name)
                                .textFieldStyle(.plain)
                                .foregroundColor(.white)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.white.opacity(0.2))
                                )
                        }

                        // Relationship picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Relationship")
                                .font(.headline)
                                .foregroundColor(.white)

                            Picker("Relationship", selection: $selectedRelationship) {
                                ForEach(RelationshipType.allCases, id: \.self) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        // Custom relationship (optional)
                        if selectedRelationship == .other {
                            TextField("Specify relationship", text: $relationship)
                                .textFieldStyle(.plain)
                                .foregroundColor(.white)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.white.opacity(0.2))
                                )
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Add VIP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveVIP()
                    }
                    .foregroundColor(.white)
                    .disabled(name.isEmpty)
                }
            }
        }
    }

    private func saveVIP() {
        let newVIP = VIPEntry(
            name: name,
            relationship: selectedRelationship == .other ? relationship : selectedRelationship.rawValue,
            photoCount: 0,
            sightingCount: 0,
            lastSeen: Date()
        )
        onSave(newVIP)
        dismiss()
    }
}

// MARK: - VIP Detail View
struct VIPDetailView: View {
    let vip: VIPEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Profile section
                        Circle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 150, height: 150)

                        Text(vip.name)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Text(vip.relationship)
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.7))

                        // Stats
                        GlassmorphicCard {
                            HStack(spacing: 40) {
                                VStack(spacing: 8) {
                                    Text("\(vip.photoCount)")
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                    Text("Photos")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                }

                                VStack(spacing: 8) {
                                    Text("\(vip.sightingCount)")
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                    Text("Sightings")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                            .padding()
                        }

                        // Recent photos
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent Photos")
                                .font(.headline)
                                .foregroundColor(.white)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(0..<5, id: \.self) { _ in
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(.white.opacity(0.1))
                                            .frame(width: 100, height: 100)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
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

// MARK: - Stat Badge
struct StatBadge: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
                Text(label)
                    .font(.caption2)
            }
        }
        .foregroundColor(.white)
    }
}

// MARK: - Supporting Types
struct VIPEntry: Identifiable {
    let id = UUID()
    let name: String
    let relationship: String
    let photoCount: Int
    let sightingCount: Int
    let lastSeen: Date
}

enum RelationshipType: String, CaseIterable {
    case family = "Family"
    case friend = "Friend"
    case colleague = "Colleague"
    case other = "Other"
}

// MARK: - Preview
struct VIPManagerView_Previews: PreviewProvider {
    static var previews: some View {
        VIPManagerView()
    }
}
