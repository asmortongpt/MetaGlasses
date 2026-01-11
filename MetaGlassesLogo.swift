import SwiftUI

struct MetaGlassesLogo: View {
    var size: CGFloat = 60
    var showText: Bool = true

    var body: some View {
        VStack(spacing: 8) {
            // Glasses icon with augmented reality theme
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.3), .purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 1.2, height: size * 1.2)
                    .blur(radius: 10)

                // Main logo background
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)

                // Glasses icon
                Image(systemName: "visionpro")
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
            }

            if showText {
                Text("MetaGlasses")
                    .font(.system(size: size * 0.25, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        }
    }
}

// Animated version for splash screen
struct AnimatedMetaGlassesLogo: View {
    @State private var isAnimating = false
    @State private var glowAnimation = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                // Animated glow
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.4), .purple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: glowAnimation ? 100 : 80, height: glowAnimation ? 100 : 80)
                    .blur(radius: 15)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: glowAnimation)

                // Main logo
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                // Icon with pulse animation
                Image(systemName: "visionpro")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(.white)
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)
            }

            Text("MetaGlasses")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .opacity(isAnimating ? 1.0 : 0.7)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)

            Text("AI-Powered Vision")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .opacity(isAnimating ? 0.8 : 0.5)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(0.3), value: isAnimating)
        }
        .onAppear {
            isAnimating = true
            glowAnimation = true
        }
    }
}

// Compact logo for navigation bar
struct CompactMetaGlassesLogo: View {
    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "visionpro")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
            }

            Text("MetaGlasses")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }
}

#Preview("Standard Logo") {
    VStack(spacing: 40) {
        MetaGlassesLogo(size: 80, showText: true)
        MetaGlassesLogo(size: 60, showText: true)
        MetaGlassesLogo(size: 40, showText: false)
    }
    .padding()
}

#Preview("Animated Logo") {
    AnimatedMetaGlassesLogo()
        .padding()
}

#Preview("Compact Logo") {
    CompactMetaGlassesLogo()
        .padding()
}
