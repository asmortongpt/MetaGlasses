import SwiftUI

/// Production-grade AI Assistant UI with voice, vision, and chat
struct EnhancedAIAssistantView: View {
    @StateObject private var voiceAssistant = VoiceAssistantService()
    @StateObject private var visionAnalysis = VisionAnalysisService()
    @StateObject private var ragService = RAGService()

    @State private var inputText = ""
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var showingVisionResults = false

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.black, Color.purple.opacity(0.3)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Conversation View
                    conversationView

                    // Input Area
                    inputArea
                }
            }
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { voiceAssistant.clearConversation() }) {
                            Label("Clear Chat", systemImage: "trash")
                        }

                        Button(action: { showingImagePicker = true }) {
                            Label("Analyze Image", systemImage: "photo")
                        }

                        Button(action: exportConversation) {
                            Label("Export Chat", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $selectedImage) { image in
                Task {
                    await analyzeImage(image)
                }
            }
        }
        .sheet(isPresented: $showingVisionResults) {
            if let result = visionAnalysis.analysisResult {
                VisionResultsView(result: result)
            }
        }
    }

    // MARK: - Conversation View
    private var conversationView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    // Welcome message
                    if voiceAssistant.conversationHistory.isEmpty {
                        welcomeMessage
                    }

                    // Messages
                    ForEach(voiceAssistant.conversationHistory) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                    }

                    // Typing indicator
                    if voiceAssistant.isSpeaking || visionAnalysis.isAnalyzing {
                        typingIndicator
                    }
                }
                .padding()
            }
            .onChange(of: voiceAssistant.conversationHistory.count) { _ in
                if let lastMessage = voiceAssistant.conversationHistory.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var welcomeMessage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.bottom, 8)

            Text("AI Assistant Ready")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text("I can help you with:")
                .font(.subheadline)
                .foregroundColor(.gray)

            VStack(alignment: .leading, spacing: 8) {
                FeatureRow(icon: "camera.viewfinder", text: "Analyze images and scenes")
                FeatureRow(icon: "mic.fill", text: "Voice commands and conversations")
                FeatureRow(icon: "book.fill", text: "Remember and recall information")
                FeatureRow(icon: "lightbulb.fill", text: "Smart suggestions and insights")
            }
            .padding(.top, 4)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }

    private var typingIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animateTyping ? 1.0 : 0.5)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: animateTyping
                    )
            }
            Text("Thinking...")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(12)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
        .onAppear { animateTyping = true }
        .onDisappear { animateTyping = false }
    }

    @State private var animateTyping = false

    // MARK: - Input Area
    private var inputArea: some View {
        VStack(spacing: 12) {
            // Quick actions
            quickActionsBar

            // Text input with voice button
            HStack(spacing: 12) {
                // Text field
                HStack {
                    TextField("Ask me anything...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                        .lineLimit(1...5)

                    if !inputText.isEmpty {
                        Button(action: { inputText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.1))
                .cornerRadius(20)

                // Voice button
                Button(action: toggleVoiceInput) {
                    Image(systemName: voiceAssistant.isListening ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            voiceAssistant.isListening ?
                            LinearGradient(colors: [.red, .orange], startPoint: .top, endPoint: .bottom) :
                            LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom)
                        )
                }
                .scaleEffect(voiceAssistant.isListening ? 1.1 : 1.0)
                .animation(.spring(), value: voiceAssistant.isListening)

                // Send button
                if !inputText.isEmpty {
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(.horizontal)

            // Voice transcript
            if voiceAssistant.isListening && !voiceAssistant.transcript.isEmpty {
                Text(voiceAssistant.transcript)
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(8)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.8))
    }

    private var quickActionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                QuickActionButton(icon: "camera.viewfinder", label: "Analyze Scene") {
                    showingImagePicker = true
                }

                QuickActionButton(icon: "book.fill", label: "Knowledge Base") {
                    Task {
                        await showKnowledgeBase()
                    }
                }

                QuickActionButton(icon: "lightbulb.fill", label: "Suggestions") {
                    Task {
                        await getSuggestions()
                    }
                }

                QuickActionButton(icon: "clock.arrow.circlepath", label: "Recent") {
                    // Show recent queries
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Actions
    private func toggleVoiceInput() {
        if voiceAssistant.isListening {
            voiceAssistant.stopListening()
        } else {
            voiceAssistant.startListening()
        }
    }

    private func sendMessage() {
        guard !inputText.isEmpty else { return }

        let message = inputText
        inputText = ""

        Task {
            await voiceAssistant.sendTextMessage(message)
        }
    }

    private func analyzeImage(_ image: UIImage) async {
        do {
            let result = try await visionAnalysis.analyzeImage(image, mode: .comprehensive)
            showingVisionResults = true

            // Add to conversation
            let message = "I analyzed the image: \(result.aiDescription)"
            await voiceAssistant.sendTextMessage("What do you see in this image?")

            // Store in knowledge base
            try await ragService.addImage(image: image, caption: result.aiDescription)
        } catch {
            print("❌ Image analysis failed: \(error)")
        }
    }

    private func showKnowledgeBase() async {
        let count = ragService.knowledgeBaseSize
        await voiceAssistant.sendTextMessage("Show me what you remember (you have \(count) items stored)")
    }

    private func getSuggestions() async {
        await voiceAssistant.sendTextMessage("What can I help you with right now?")
    }

    private func exportConversation() {
        // Export conversation logic
        print("📤 Exporting conversation...")
    }
}

// MARK: - Supporting Views
struct MessageBubbleView: View {
    let message: ConversationMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    .background(
                        message.role == .user ?
                        LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing) :
                        Color.white.opacity(0.1)
                    )
                    .foregroundColor(.white)
                    .cornerRadius(16)
                    .contextMenu {
                        Button(action: { UIPasteboard.general.string = message.content }) {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        Button(action: { /* Speak */ }) {
                            Label("Speak", systemImage: "speaker.wave.2")
                        }
                    }

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            if message.role != .user { Spacer(minLength: 60) }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption2)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

// MARK: - Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let onImageSelected: (UIImage) -> Void
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
                parent.onImageSelected(image)
            }
            parent.dismiss()
        }
    }
}

// MARK: - Vision Results View
struct VisionResultsView: View {
    let result: VisionAnalysisResult
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Image
                    Image(uiImage: result.originalImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(12)

                    // AI Description
                    SectionView(title: "AI Analysis", icon: "brain") {
                        Text(result.aiDescription)
                            .foregroundColor(.white)
                    }

                    // Detected Objects
                    if let objects = result.appleVisionData?.detectedObjects, !objects.isEmpty {
                        SectionView(title: "Detected Objects", icon: "viewfinder") {
                            ForEach(objects) { obj in
                                HStack {
                                    Text(obj.displayName)
                                    Spacer()
                                    Text("\(obj.confidencePercent)%")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }

                    // Smart Suggestions
                    if !result.suggestions.isEmpty {
                        SectionView(title: "Suggestions", icon: "lightbulb") {
                            ForEach(result.suggestions, id: \.self) { suggestion in
                                Text(suggestion)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("Vision Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct SectionView<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
            }

            content
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}
