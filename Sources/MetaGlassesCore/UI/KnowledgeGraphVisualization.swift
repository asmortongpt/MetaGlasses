import SwiftUI
import SceneKit
import Combine

/// Interactive 3D Knowledge Graph Visualization
/// Displays memories, relationships, and context in beautiful 3D space
@MainActor
public struct KnowledgeGraphVisualization: View {

    // MARK: - State Management
    @StateObject private var graphManager = KnowledgeGraphManager()
    @StateObject private var timelineManager = TimelineManager()

    @State private var selectedNode: GraphNode?
    @State private var showingNodeDetail = false
    @State private var viewMode: ViewMode = .graph3D
    @State private var filterMode: FilterMode = .all
    @State private var searchText = ""
    @State private var showingTimeline = false
    @State private var animateNodes = true

    @Environment(\.dismiss) var dismiss

    // MARK: - Body
    public var body: some View {
        NavigationStack {
            ZStack {
                // Background
                backgroundGradient

                // Main Content
                VStack(spacing: 0) {
                    // Search & Filter Bar
                    searchFilterBar
                        .padding()

                    // View Mode Selector
                    viewModeSelector
                        .padding(.horizontal)

                    // Main Visualization
                    mainVisualizationArea
                        .frame(maxHeight: .infinity)

                    // Stats Bar
                    statsBar
                        .padding()
                }
            }
            .navigationTitle("Knowledge Graph")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: exportGraph) {
                            Label("Export Graph", systemImage: "square.and.arrow.up")
                        }
                        Button(action: clearGraph) {
                            Label("Clear Graph", systemImage: "trash")
                        }
                        Toggle("Animate Nodes", isOn: $animateNodes)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.white)
                    }
                }
            }
            .sheet(isPresented: $showingNodeDetail) {
                if let node = selectedNode {
                    NodeDetailView(node: node)
                }
            }
            .sheet(isPresented: $showingTimeline) {
                TimelineView(manager: timelineManager)
            }
            .onAppear {
                loadGraphData()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Background Gradient
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(hex: "0a0e27"),
                Color(hex: "1a1a2e"),
                Color(hex: "16213e")
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Search & Filter Bar
    private var searchFilterBar: some View {
        HStack(spacing: 12) {
            // Search Field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.6))

                TextField("Search memories...", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)

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

            // Filter Button
            Menu {
                ForEach(FilterMode.allCases, id: \.self) { mode in
                    Button(action: { filterMode = mode }) {
                        HStack {
                            Text(mode.displayName)
                            if filterMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.title2)
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: - View Mode Selector
    private var viewModeSelector: some View {
        HStack(spacing: 16) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Button(action: {
                    withAnimation(.spring()) {
                        viewMode = mode
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: mode.icon)
                            .font(.callout)
                        Text(mode.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(viewMode == mode ? .white : .white.opacity(0.5))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(viewMode == mode ? .white.opacity(0.2) : .clear)
                    )
                }
            }
        }
    }

    // MARK: - Main Visualization Area
    @ViewBuilder
    private var mainVisualizationArea: some View {
        switch viewMode {
        case .graph3D:
            graph3DView
        case .timeline:
            timelineView
        case .cluster:
            clusterView
        case .network:
            networkView
        }
    }

    // MARK: - 3D Graph View
    private var graph3DView: some View {
        GeometryReader { geometry in
            ZStack {
                // SceneKit 3D View
                SceneKitGraphView(
                    nodes: graphManager.filteredNodes(searchText: searchText, filter: filterMode),
                    edges: graphManager.edges,
                    selectedNode: $selectedNode,
                    animate: animateNodes,
                    onNodeTap: { node in
                        selectedNode = node
                        showingNodeDetail = true
                    }
                )

                // Overlay Controls
                VStack {
                    Spacer()

                    HStack {
                        Spacer()

                        // 3D Controls
                        VStack(spacing: 12) {
                            controlButton(icon: "rotate.3d", label: "Rotate") {
                                graphManager.rotateGraph()
                            }

                            controlButton(icon: "arrow.up.left.and.arrow.down.right", label: "Reset") {
                                graphManager.resetCamera()
                            }

                            controlButton(icon: "plus.magnifyingglass", label: "Zoom In") {
                                graphManager.zoomIn()
                            }

                            controlButton(icon: "minus.magnifyingglass", label: "Zoom Out") {
                                graphManager.zoomOut()
                            }
                        }
                        .padding()
                    }
                }
            }
        }
    }

    private func controlButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.3), radius: 5)
                )
        }
    }

    // MARK: - Timeline View
    private var timelineView: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(timelineManager.timelineEvents) { event in
                    TimelineEventCard(event: event)
                        .onTapGesture {
                            selectedNode = event.associatedNode
                            showingNodeDetail = true
                        }
                }
            }
            .padding()
        }
    }

    // MARK: - Cluster View
    private var clusterView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                ForEach(graphManager.clusters) { cluster in
                    ClusterCard(cluster: cluster)
                        .onTapGesture {
                            // Show cluster details
                        }
                }
            }
            .padding()
        }
    }

    // MARK: - Network View
    private var networkView: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                drawNetworkGraph(
                    context: context,
                    size: size,
                    nodes: graphManager.filteredNodes(searchText: searchText, filter: filterMode),
                    edges: graphManager.edges
                )
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Handle node dragging
                    }
            )
        }
    }

    private func drawNetworkGraph(context: GraphicsContext, size: CGSize, nodes: [GraphNode], edges: [GraphEdge]) {
        // Draw edges
        for edge in edges {
            if let fromNode = nodes.first(where: { $0.id == edge.fromId }),
               let toNode = nodes.first(where: { $0.id == edge.toId }) {

                var path = Path()
                path.move(to: fromNode.position)
                path.addLine(to: toNode.position)

                context.stroke(
                    path,
                    with: .color(.white.opacity(0.2)),
                    lineWidth: CGFloat(edge.strength) * 2
                )
            }
        }

        // Draw nodes
        for node in nodes {
            let circle = Circle()
                .path(in: CGRect(
                    x: node.position.x - node.radius,
                    y: node.position.y - node.radius,
                    width: node.radius * 2,
                    height: node.radius * 2
                ))

            context.fill(circle, with: .color(node.color))
            context.stroke(circle, with: .color(.white.opacity(0.5)), lineWidth: 2)
        }
    }

    // MARK: - Stats Bar
    private var statsBar: some View {
        HStack(spacing: 24) {
            statItem(
                icon: "circle.grid.3x3.fill",
                value: "\(graphManager.totalNodes)",
                label: "Memories"
            )

            Divider()
                .frame(height: 30)
                .background(Color.white.opacity(0.3))

            statItem(
                icon: "link",
                value: "\(graphManager.totalEdges)",
                label: "Connections"
            )

            Divider()
                .frame(height: 30)
                .background(Color.white.opacity(0.3))

            statItem(
                icon: "person.2.fill",
                value: "\(graphManager.totalPeople)",
                label: "People"
            )

            Spacer()

            Button(action: { showingTimeline = true }) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3)
                    .foregroundColor(.white)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    private func statItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))

            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
        }
    }

    // MARK: - Data Loading & Actions
    private func loadGraphData() {
        Task {
            await graphManager.loadGraph()
            await timelineManager.loadTimeline()
        }
    }

    private func exportGraph() {
        print("📤 Exporting knowledge graph...")
    }

    private func clearGraph() {
        print("🗑️ Clearing knowledge graph...")
    }
}

// MARK: - SceneKit Graph View
struct SceneKitGraphView: UIViewRepresentable {
    let nodes: [GraphNode]
    let edges: [GraphEdge]
    @Binding var selectedNode: GraphNode?
    let animate: Bool
    let onNodeTap: (GraphNode) -> Void

    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.scene = createScene()
        sceneView.backgroundColor = .clear
        sceneView.allowsCameraControl = true
        sceneView.autoenablesDefaultLighting = true
        sceneView.defaultCameraController.interactionMode = .orbitTurntable

        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleTap(_:)))
        sceneView.addGestureRecognizer(tapGesture)

        return sceneView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Update scene with new data
        if let scene = uiView.scene {
            updateScene(scene, with: nodes, edges: edges)
        }
    }

    private func createScene() -> SCNScene {
        let scene = SCNScene()

        // Add camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 15)
        scene.rootNode.addChildNode(cameraNode)

        // Add ambient light
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.color = UIColor.white
        ambientLight.light?.intensity = 200
        scene.rootNode.addChildNode(ambientLight)

        return scene
    }

    private func updateScene(_ scene: SCNScene, with nodes: [GraphNode], edges: [GraphEdge]) {
        // Remove existing nodes
        scene.rootNode.childNodes.forEach { node in
            if node.name?.hasPrefix("graphNode") == true || node.name == "edge" {
                node.removeFromParentNode()
            }
        }

        // Add nodes
        for node in nodes {
            let sphere = SCNSphere(radius: CGFloat(node.radius) / 100)
            sphere.firstMaterial?.diffuse.contents = UIColor(node.color)
            sphere.firstMaterial?.emission.contents = UIColor(node.color.opacity(0.3))

            let sphereNode = SCNNode(geometry: sphere)
            sphereNode.position = SCNVector3(
                Float(node.position.x) / 50 - 5,
                Float(node.position.y) / 50 - 5,
                0
            )
            sphereNode.name = "graphNode_\(node.id)"

            // Add animation if enabled
            if animate {
                let rotation = SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 10)
                let repeatAction = SCNAction.repeatForever(rotation)
                sphereNode.runAction(repeatAction)
            }

            scene.rootNode.addChildNode(sphereNode)
        }

        // Add edges
        for edge in edges {
            if let fromNode = nodes.first(where: { $0.id == edge.fromId }),
               let toNode = nodes.first(where: { $0.id == edge.toId }) {

                let line = createLineBetween(
                    from: fromNode.position,
                    to: toNode.position,
                    strength: edge.strength
                )
                scene.rootNode.addChildNode(line)
            }
        }
    }

    private func createLineBetween(from: CGPoint, to: CGPoint, strength: Float) -> SCNNode {
        let vector = SCNVector3(
            Float(to.x - from.x) / 50,
            Float(to.y - from.y) / 50,
            0
        )
        let distance = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)

        let cylinder = SCNCylinder(radius: CGFloat(strength) / 200, height: CGFloat(distance))
        cylinder.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.3)

        let lineNode = SCNNode(geometry: cylinder)
        lineNode.position = SCNVector3(
            Float(from.x) / 50 - 5 + vector.x / 2,
            Float(from.y) / 50 - 5 + vector.y / 2,
            vector.z / 2
        )
        lineNode.name = "edge"

        return lineNode
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject {
        let parent: SceneKitGraphView

        init(parent: SceneKitGraphView) {
            self.parent = parent
        }

        @objc func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
            guard let sceneView = gestureRecognizer.view as? SCNView else { return }

            let location = gestureRecognizer.location(in: sceneView)
            let hitResults = sceneView.hitTest(location, options: [:])

            if let hitNode = hitResults.first?.node,
               let nodeName = hitNode.name,
               nodeName.hasPrefix("graphNode_"),
               let nodeIdString = nodeName.split(separator: "_").last,
               let nodeId = UUID(uuidString: String(nodeIdString)),
               let node = parent.nodes.first(where: { $0.id == nodeId }) {

                parent.onNodeTap(node)
            }
        }
    }
}

// MARK: - Timeline Event Card
struct TimelineEventCard: View {
    let event: TimelineEvent

    var body: some View {
        HStack(spacing: 16) {
            // Timeline Indicator
            VStack {
                Circle()
                    .fill(event.color)
                    .frame(width: 12, height: 12)

                Rectangle()
                    .fill(event.color.opacity(0.3))
                    .frame(width: 2)
            }

            // Content
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(event.title)
                        .font(.headline)
                        .foregroundColor(.white)

                    Spacer()

                    Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }

                Text(event.description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(2)

                // Tags
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(event.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(event.color.opacity(0.3))
                                )
                                .foregroundColor(.white)
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
}

// MARK: - Cluster Card
struct ClusterCard: View {
    let cluster: MemoryCluster

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: cluster.icon)
                    .font(.title2)
                    .foregroundColor(cluster.color)

                Spacer()

                Text("\(cluster.nodeCount)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }

            // Title
            Text(cluster.title)
                .font(.headline)
                .foregroundColor(.white)

            // Description
            Text(cluster.description)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(2)

            // Progress Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.white.opacity(0.1))
                        .frame(height: 4)

                    Rectangle()
                        .fill(cluster.color)
                        .frame(width: geometry.size.width * CGFloat(cluster.strength), height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.05))
        )
    }
}

// MARK: - Node Detail View
struct NodeDetailView: View {
    let node: GraphNode
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Node Icon/Image
                    Circle()
                        .fill(node.color)
                        .frame(width: 100, height: 100)
                        .overlay(
                            Image(systemName: node.icon)
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                        )
                        .frame(maxWidth: .infinity)

                    // Title
                    Text(node.title)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .center)

                    // Metadata
                    VStack(alignment: .leading, spacing: 12) {
                        detailRow(icon: "calendar", label: "Created", value: node.timestamp.formatted())
                        detailRow(icon: "link", label: "Connections", value: "\(node.connectionCount)")
                        detailRow(icon: "tag", label: "Category", value: node.category.displayName)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(0.05))
                    )

                    // Description
                    if !node.description.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.headline)
                                .foregroundColor(.white)

                            Text(node.description)
                                .font(.body)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.white.opacity(0.05))
                        )
                    }

                    // Related Nodes
                    if !node.relatedNodes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Related Memories")
                                .font(.headline)
                                .foregroundColor(.white)

                            ForEach(node.relatedNodes.prefix(5), id: \.self) { relatedId in
                                Text("Related Node: \(relatedId.uuidString.prefix(8))")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.white.opacity(0.05))
                        )
                    }
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("Memory Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)

            Text(label)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
        }
    }
}

// MARK: - Supporting Types
enum ViewMode: String, CaseIterable {
    case graph3D, timeline, cluster, network

    var displayName: String {
        switch self {
        case .graph3D: return "3D Graph"
        case .timeline: return "Timeline"
        case .cluster: return "Clusters"
        case .network: return "Network"
        }
    }

    var icon: String {
        switch self {
        case .graph3D: return "cube.fill"
        case .timeline: return "clock.fill"
        case .cluster: return "square.grid.3x2.fill"
        case .network: return "network"
        }
    }
}

enum FilterMode: String, CaseIterable {
    case all, people, places, events, recent

    var displayName: String {
        switch self {
        case .all: return "All Memories"
        case .people: return "People"
        case .places: return "Places"
        case .events: return "Events"
        case .recent: return "Recent"
        }
    }
}

enum NodeCategory: String {
    case person, place, event, object

    var displayName: String {
        switch self {
        case .person: return "Person"
        case .place: return "Place"
        case .event: return "Event"
        case .object: return "Object"
        }
    }
}

struct GraphNode: Identifiable, Equatable {
    let id: UUID
    let title: String
    let description: String
    let category: NodeCategory
    let timestamp: Date
    let position: CGPoint
    let radius: CGFloat
    let color: Color
    let icon: String
    let connectionCount: Int
    let relatedNodes: [UUID]

    static func == (lhs: GraphNode, rhs: GraphNode) -> Bool {
        lhs.id == rhs.id
    }
}

struct GraphEdge: Identifiable {
    let id = UUID()
    let fromId: UUID
    let toId: UUID
    let strength: Float // 0.0 to 1.0
    let label: String?
}

struct TimelineEvent: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let timestamp: Date
    let tags: [String]
    let color: Color
    let associatedNode: GraphNode
}

struct MemoryCluster: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String
    let color: Color
    let nodeCount: Int
    let strength: Float
}

// MARK: - Managers
@MainActor
class KnowledgeGraphManager: ObservableObject {
    @Published var nodes: [GraphNode] = []
    @Published var edges: [GraphEdge] = []
    @Published var clusters: [MemoryCluster] = []

    var totalNodes: Int { nodes.count }
    var totalEdges: Int { edges.count }
    var totalPeople: Int {
        nodes.filter { $0.category == .person }.count
    }

    func loadGraph() async {
        // Simulate loading graph data
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Generate sample nodes
        nodes = (0..<20).map { index in
            GraphNode(
                id: UUID(),
                title: "Memory \(index + 1)",
                description: "Description for memory \(index + 1)",
                category: NodeCategory.allCases.randomElement() ?? .event,
                timestamp: Date().addingTimeInterval(TimeInterval(-index * 86400)),
                position: CGPoint(
                    x: CGFloat.random(in: 50...350),
                    y: CGFloat.random(in: 50...550)
                ),
                radius: CGFloat.random(in: 20...40),
                color: [Color.blue, .purple, .pink, .orange, .green].randomElement() ?? .blue,
                icon: ["person.fill", "mappin.circle.fill", "calendar", "camera.fill"].randomElement() ?? "circle.fill",
                connectionCount: Int.random(in: 1...10),
                relatedNodes: []
            )
        }

        // Generate sample edges
        edges = (0..<30).compactMap { _ in
            guard nodes.count >= 2 else { return nil }
            let from = nodes.randomElement()!
            let to = nodes.randomElement()!
            guard from.id != to.id else { return nil }

            return GraphEdge(
                fromId: from.id,
                toId: to.id,
                strength: Float.random(in: 0.3...1.0),
                label: nil
            )
        }

        // Generate clusters
        clusters = (0..<4).map { index in
            MemoryCluster(
                title: ["Work", "Family", "Travel", "Hobbies"][index],
                description: "Cluster of related memories",
                icon: ["briefcase.fill", "person.2.fill", "airplane", "paintbrush.fill"][index],
                color: [.blue, .purple, .orange, .green][index],
                nodeCount: Int.random(in: 5...15),
                strength: Float.random(in: 0.5...1.0)
            )
        }
    }

    func filteredNodes(searchText: String, filter: FilterMode) -> [GraphNode] {
        var filtered = nodes

        // Apply filter
        switch filter {
        case .all:
            break
        case .people:
            filtered = filtered.filter { $0.category == .person }
        case .places:
            filtered = filtered.filter { $0.category == .place }
        case .events:
            filtered = filtered.filter { $0.category == .event }
        case .recent:
            filtered = filtered.filter { $0.timestamp > Date().addingTimeInterval(-7 * 86400) }
        }

        // Apply search
        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }

        return filtered
    }

    func rotateGraph() {
        print("🔄 Rotating graph...")
    }

    func resetCamera() {
        print("📷 Resetting camera...")
    }

    func zoomIn() {
        print("🔍 Zooming in...")
    }

    func zoomOut() {
        print("🔍 Zooming out...")
    }
}

@MainActor
class TimelineManager: ObservableObject {
    @Published var timelineEvents: [TimelineEvent] = []

    func loadTimeline() async {
        // Simulate loading timeline
        try? await Task.sleep(nanoseconds: 500_000_000)

        // This would connect to actual data
        timelineEvents = []
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

// MARK: - NodeCategory Extension
extension NodeCategory: CaseIterable {
    static var allCases: [NodeCategory] {
        [.person, .place, .event, .object]
    }
}
