import SwiftUI
import Combine
import MarkdownUI
import AVFoundation

// MARK: - Enhanced AI Assistant View with Professional UI
struct EnhancedAIAssistantView: View {
    @StateObject private var openAIService = EnhancedOpenAIService(apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"])
    @StateObject private var voiceService = VoiceAssistantService()
    @StateObject private var visionService = AdvancedVisionService()
    @StateObject private var offlineManager = OfflineManager()

    @State private var inputText = ""
    @State private var messages: [MessageBubble] = []
    @State private var isTyping = false
    @State private var showingImagePicker = false
    @State private var selectedImages: [UIImage] = []
    @State private var showingSettings = false
    @State private var showingSuggestions = true
    @State private var selectedModel: EnhancedOpenAIService.Model = .gpt4Turbo
    @State private var scrollViewProxy: ScrollViewProxy?
    @State private var keyboardHeight: CGFloat = 0

    @FocusState private var isInputFocused: Bool

    // Animation states
    @State private var typingDots = ""
    @State private var streamingOpacity = 1.0

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.black, Color.blue.opacity(0.1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Status bar
                    statusBar

                    // Messages
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(messages) { message in
                                    MessageView(message: message)
                                        .id(message.id)
                                }

                                if !openAIService.streamingText.isEmpty {
                                    StreamingMessageView(text: openAIService.streamingText)
                                        .id("streaming")
                                        .opacity(streamingOpacity)
                                        .onAppear {
                                            withAnimation(.easeIn(duration: 0.3)) {
                                                streamingOpacity = 1.0
                                            }
                                        }
                                }

                                if isTyping {
                                    TypingIndicator()
                                        .id("typing")
                                }
                            }
                            .padding()
                        }
                        .onAppear {
                            scrollViewProxy = proxy
                        }
                        .onChange(of: messages.count) { _ in
                            scrollToBottom(proxy: proxy)
                        }
                        .onChange(of: openAIService.streamingText) { _ in
                            scrollToBottom(proxy: proxy)
                        }
                    }

                    // Suggestions
                    if showingSuggestions && messages.isEmpty {
                        suggestionChips
                    }

                    // Input area
                    inputArea
                }
            }
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        connectionIndicator
                        settingsButton
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsSheet(selectedModel: $selectedModel)
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(images: $selectedImages)
            }
            .onReceive(Publishers.keyboardHeight) { height in
                withAnimation(.spring()) {
                    keyboardHeight = height
                }
            }
        }
    }

    // MARK: - Status Bar
    private var statusBar: some View {
        HStack {
            // Model indicator
            Label(selectedModel.rawValue, systemImage: "cpu")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)

            Spacer()

            // Connection quality
            if openAIService.connectionQuality != .excellent {
                ConnectionQualityIndicator(quality: openAIService.connectionQuality)
            }

            // Voice indicator
            if voiceService.isListening {
                HStack(spacing: 4) {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.red)
                        .font(.caption)

                    AudioWaveform(amplitude: voiceService.audioLevel)
                        .frame(width: 30, height: 16)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.2))
                .cornerRadius(12)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.3))
    }

    // MARK: - Suggestion Chips
    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(suggestions, id: \.self) { suggestion in
                    SuggestionChip(text: suggestion) {
                        inputText = suggestion
                        sendMessage()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color.white.opacity(0.05))
    }

    private var suggestions: [String] {
        [
            "📸 Analyze what I'm seeing",
            "🎯 Identify objects around me",
            "📝 Extract text from image",
            "🗺️ Where am I?",
            "💡 Give me ideas for...",
            "🔍 Research topic...",
            "✨ Help me with..."
        ]
    }

    // MARK: - Input Area
    private var inputArea: some View {
        VStack(spacing: 0) {
            // Selected images preview
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                            ImageThumbnail(image: image) {
                                selectedImages.remove(at: index)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color.white.opacity(0.05))
            }

            // Text input
            HStack(spacing: 12) {
                // Attach button
                Button(action: { showingImagePicker = true }) {
                    Image(systemName: "paperclip")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.7))
                }

                // Voice button
                Button(action: toggleVoice) {
                    Image(systemName: voiceService.isListening ? "mic.fill" : "mic")
                        .font(.title3)
                        .foregroundColor(voiceService.isListening ? .red : .white.opacity(0.7))
                        .scaleEffect(voiceService.isListening ? 1.2 : 1.0)
                        .animation(.spring(), value: voiceService.isListening)
                }

                // Text field
                ExpandingTextField(
                    text: $inputText,
                    placeholder: "Ask anything...",
                    isEnabled: !openAIService.isProcessing
                )
                .focused($isInputFocused)
                .onSubmit {
                    sendMessage()
                }

                // Send button
                SendButton(
                    isEnabled: !inputText.isEmpty && !openAIService.isProcessing,
                    isProcessing: openAIService.isProcessing
                ) {
                    sendMessage()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.1))
        }
    }

    // MARK: - Actions
    private func sendMessage() {
        guard !inputText.isEmpty else { return }

        let text = inputText
        let images = selectedImages

        // Add user message
        let userMessage = MessageBubble(
            id: UUID(),
            text: text,
            isUser: true,
            images: images,
            timestamp: Date()
        )
        messages.append(userMessage)

        // Clear input
        inputText = ""
        selectedImages = []
        isInputFocused = false

        // Show typing indicator
        isTyping = true

        // Send to AI
        Task {
            await openAIService.streamChat(message: text, images: images)
            isTyping = false

            // Add AI response
            if !openAIService.streamingText.isEmpty {
                let aiMessage = MessageBubble(
                    id: UUID(),
                    text: openAIService.streamingText,
                    isUser: false,
                    timestamp: Date()
                )
                messages.append(aiMessage)
                openAIService.streamingText = ""
            }
        }
    }

    private func toggleVoice() {
        if voiceService.isListening {
            voiceService.stopListening()
        } else {
            voiceService.startListening(mode: .conversation)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.spring()) {
            if !openAIService.streamingText.isEmpty {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else if isTyping {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let lastMessage = messages.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }

    // MARK: - Helper Views
    private var connectionIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(offlineManager.isOnline ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(offlineManager.connectionType.description)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private var settingsButton: some View {
        Button(action: { showingSettings = true }) {
            Image(systemName: "gearshape.fill")
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

// MARK: - Message Bubble
struct MessageBubble: Identifiable {
    let id: UUID
    let text: String
    let isUser: Bool
    var images: [UIImage]?
    let timestamp: Date
    var reactions: [Reaction]?
    var functionCalls: [String]?

    struct Reaction {
        let emoji: String
        let count: Int
    }
}

// MARK: - Message View
struct MessageView: View {
    let message: MessageBubble
    @State private var showingActions = false
    @State private var isCopied = false

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 60) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                // Images if present
                if let images = message.images, !images.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 150, height: 150)
                                    .cornerRadius(12)
                                    .clipped()
                            }
                        }
                    }
                }

                // Message bubble
                VStack(alignment: .leading, spacing: 4) {
                    if message.text.contains("```") {
                        CodeBlockView(text: message.text)
                    } else {
                        Text(message.text)
                            .font(.system(size: 16))
                            .foregroundColor(message.isUser ? .white : .primary)
                            .textSelection(.enabled)
                    }

                    // Function calls
                    if let functionCalls = message.functionCalls {
                        ForEach(functionCalls, id: \.self) { call in
                            HStack(spacing: 4) {
                                Image(systemName: "function")
                                    .font(.caption2)
                                Text(call)
                                    .font(.caption)
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }

                    // Timestamp
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(
                    message.isUser ?
                    AnyView(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    ) :
                    AnyView(Color.white.opacity(0.1))
                )
                .cornerRadius(16, corners: message.isUser ? [.topLeft, .topRight, .bottomLeft] : [.topLeft, .topRight, .bottomRight])
                .contextMenu {
                    Button(action: copyMessage) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }

                    Button(action: shareMessage) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }

                    if !message.isUser {
                        Button(action: regenerateMessage) {
                            Label("Regenerate", systemImage: "arrow.clockwise")
                        }
                    }
                }

                // Reactions
                if let reactions = message.reactions, !reactions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(reactions, id: \.emoji) { reaction in
                            ReactionBubble(reaction: reaction)
                        }
                    }
                }
            }

            if !message.isUser { Spacer(minLength: 60) }
        }
    }

    private func copyMessage() {
        UIPasteboard.general.string = message.text
        isCopied = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopied = false
        }
    }

    private func shareMessage() {
        // Implement share functionality
    }

    private func regenerateMessage() {
        // Implement regenerate functionality
    }
}

// MARK: - Streaming Message View
struct StreamingMessageView: View {
    let text: String
    @State private var displayedText = ""
    @State private var currentIndex = 0

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayedText)
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    + Text("▊")
                    .foregroundColor(.blue)
                    .blinking()

                Text(Date(), style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.white.opacity(0.1))
            .cornerRadius(16, corners: [.topLeft, .topRight, .bottomRight])

            Spacer(minLength: 60)
        }
        .onAppear {
            animateText()
        }
        .onChange(of: text) { _ in
            animateText()
        }
    }

    private func animateText() {
        displayedText = text
    }
}

// MARK: - Code Block View
struct CodeBlockView: View {
    let text: String
    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(detectLanguage())
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: copyCode) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.3))

            // Code
            ScrollView(.horizontal, showsIndicators: false) {
                Text(extractCode())
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.primary)
                    .padding(12)
            }
            .background(Color.black.opacity(0.2))
        }
        .cornerRadius(8)
    }

    private func detectLanguage() -> String {
        if text.contains("```swift") { return "Swift" }
        if text.contains("```python") { return "Python" }
        if text.contains("```javascript") { return "JavaScript" }
        if text.contains("```json") { return "JSON" }
        return "Code"
    }

    private func extractCode() -> String {
        let pattern = "```[\\w]*\\n([\\s\\S]*?)```"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            return String(text[range])
        }
        return text
    }

    private func copyCode() {
        UIPasteboard.general.string = extractCode()
        isCopied = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopied = false
        }
    }
}

// MARK: - Typing Indicator
struct TypingIndicator: View {
    @State private var animatingDot = 0

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: 8, height: 8)
                        .scaleEffect(animatingDot == index ? 1.2 : 0.8)
                        .animation(
                            .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                            value: animatingDot
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.1))
            .cornerRadius(16, corners: [.topLeft, .topRight, .bottomRight])

            Spacer(minLength: 60)
        }
        .onAppear {
            animatingDot = -1
        }
    }
}

// MARK: - Suggestion Chip
struct SuggestionChip: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Expanding Text Field
struct ExpandingTextField: View {
    @Binding var text: String
    let placeholder: String
    let isEnabled: Bool
    @State private var textHeight: CGFloat = 40

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 12)
            }

            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .foregroundColor(.white)
                .frame(minHeight: 40, maxHeight: 120)
                .fixedSize(horizontal: false, vertical: true)
                .disabled(!isEnabled)
                .padding(.horizontal, 8)
        }
        .padding(4)
        .background(Color.white.opacity(0.1))
        .cornerRadius(20)
    }
}

// MARK: - Send Button
struct SendButton: View {
    let isEnabled: Bool
    let isProcessing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isProcessing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(isEnabled ? .blue : .gray)
                }
            }
            .frame(width: 36, height: 36)
        }
        .disabled(!isEnabled || isProcessing)
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Image Thumbnail
struct ImageThumbnail: View {
    let image: UIImage
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .cornerRadius(8)
                .clipped()

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.white)
                    .background(Circle().fill(Color.black.opacity(0.6)))
            }
            .offset(x: 6, y: -6)
        }
    }
}

// MARK: - Connection Quality Indicator
struct ConnectionQualityIndicator: View {
    let quality: ConnectionQuality

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < signalBars ? quality.color : Color.gray.opacity(0.3))
                    .frame(width: 3, height: CGFloat(4 + index * 2))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.1))
        .cornerRadius(8)
    }

    private var signalBars: Int {
        switch quality {
        case .excellent: return 4
        case .good: return 3
        case .fair: return 2
        case .poor: return 1
        case .offline: return 0
        }
    }
}

// MARK: - Audio Waveform
struct AudioWaveform: View {
    let amplitude: Float
    @State private var bars: [CGFloat] = [0.3, 0.5, 0.4, 0.6, 0.3]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: 3, height: bars[index] * 16)
                    .animation(.spring(), value: bars[index])
            }
        }
        .onAppear {
            animateBars()
        }
    }

    private func animateBars() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            for i in 0..<bars.count {
                bars[i] = CGFloat.random(in: 0.3...1.0) * CGFloat(amplitude * 10)
            }
        }
    }
}

// MARK: - Reaction Bubble
struct ReactionBubble: View {
    let reaction: MessageBubble.Reaction

    var body: some View {
        HStack(spacing: 2) {
            Text(reaction.emoji)
                .font(.caption)
            if reaction.count > 1 {
                Text("\(reaction.count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Settings Sheet
struct SettingsSheet: View {
    @Binding var selectedModel: EnhancedOpenAIService.Model
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Model") {
                    Picker("AI Model", selection: $selectedModel) {
                        ForEach(EnhancedOpenAIService.Model.allCases, id: \.self) { model in
                            Label {
                                VStack(alignment: .leading) {
                                    Text(model.rawValue)
                                        .font(.headline)
                                    Text("Context: \(model.contextWindow) tokens")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Image(systemName: model.supportsVision ? "eye" : "brain")
                                    .foregroundColor(model.supportsVision ? .blue : .gray)
                            }
                        }
                    }
                }

                Section("Features") {
                    Toggle("Streaming Responses", isOn: .constant(true))
                    Toggle("Voice Input", isOn: .constant(true))
                    Toggle("Offline Mode", isOn: .constant(true))
                    Toggle("Smart Suggestions", isOn: .constant(true))
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Helper Extensions
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }

    func blinking() -> some View {
        opacity(1)
            .animation(.easeInOut(duration: 0.5).repeatForever(), value: true)
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(), value: configuration.isPressed)
    }
}

// MARK: - Keyboard Height Publisher
extension Publishers {
    static var keyboardHeight: AnyPublisher<CGFloat, Never> {
        let willShow = NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .compactMap { $0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect }
            .map { $0.height }

        let willHide = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ in CGFloat(0) }

        return MergeMany(willShow, willHide)
            .eraseToAnyPublisher()
    }
}

// MARK: - Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var images: [UIImage]
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = false
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
                parent.images.append(image)
            }
            parent.dismiss()
        }
    }
}