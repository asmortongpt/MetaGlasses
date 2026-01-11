import SwiftUI

/// Photo Detail View with AI Analysis
@MainActor
public struct PhotoDetailView: View {

    let photo: GalleryPhoto
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false
    @State private var showingEditOptions = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack {
                    // Photo
                    Rectangle()
                        .fill(.gray.opacity(0.2))
                        .aspectRatio(4/3, contentMode: .fit)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 80))
                                .foregroundColor(.white.opacity(0.3))
                        )

                    // Info section
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // Recognized people
                            if !photo.recognizedPeople.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Label("People", systemImage: "person.2.fill")
                                        .font(.headline)
                                        .foregroundColor(.white)

                                    ForEach(photo.recognizedPeople, id: \.self) { person in
                                        HStack {
                                            Circle()
                                                .fill(.white.opacity(0.2))
                                                .frame(width: 40, height: 40)
                                            Text(person)
                                                .foregroundColor(.white)
                                            Spacer()
                                        }
                                    }
                                }
                            }

                            // Location
                            if let location = photo.location {
                                Label(location, systemImage: "map.fill")
                                    .foregroundColor(.white)
                            }

                            // Tags
                            if !photo.tags.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Tags")
                                        .font(.headline)
                                        .foregroundColor(.white)

                                    FlowLayout(spacing: 8) {
                                        ForEach(photo.tags, id: \.self) { tag in
                                            Text(tag)
                                                .font(.caption)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Capsule().fill(.white.opacity(0.2)))
                                                .foregroundColor(.white)
                                        }
                                    }
                                }
                            }

                            // Timestamp
                            Text(photo.timestamp.formatted(date: .long, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button {
                            showingShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.white)
                        }

                        Button {
                            showingEditOptions = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.width ?? 0,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))
                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }

            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}
