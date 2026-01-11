import UIKit
import CoreImage
import Vision
import CoreML

/// AI-powered image enhancement system
/// Automatically identifies subjects, crops, edits, and exports optimized images
public class AIImageEnhancer {

    // MARK: - Properties

    private let ciContext: CIContext
    private let visionQueue = DispatchQueue(label: "com.metaglasses.vision", qos: .userInitiated)

    // MARK: - Initialization

    public init() {
        self.ciContext = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            .cacheIntermediates: true,
            .useSoftwareRenderer: false
        ])
    }

    // MARK: - Public API

    /// Enhance image with AI-powered improvements
    /// - Parameter image: Original captured image
    /// - Returns: Enhanced, cropped, and optimized image
    public func enhance(_ image: UIImage) async throws -> EnhancedImage {
        print("🎨 Starting AI image enhancement...")

        // Step 1: Analyze image content
        let analysis = try await analyzeImage(image)

        // Step 2: Intelligent cropping based on subject
        let cropped = try cropToSubject(image, analysis: analysis)

        // Step 3: AI-powered editing
        let edited = try await applyIntelligentEdits(cropped, analysis: analysis)

        // Step 4: Final optimization
        let optimized = try optimizeForExport(edited)

        print("✅ AI enhancement complete!")

        return EnhancedImage(
            original: image,
            enhanced: optimized,
            analysis: analysis,
            improvements: [
                "Intelligent Crop",
                "Auto Color Balance",
                "Exposure Optimization",
                "Sharpness Enhancement",
                "Noise Reduction"
            ]
        )
    }

    // MARK: - Image Analysis

    private func analyzeImage(_ image: UIImage) async throws -> ImageAnalysis {
        guard let cgImage = image.cgImage else {
            throw EnhancementError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            visionQueue.async {
                do {
                    // Detect faces
                    let faceRequest = VNDetectFaceRectanglesRequest()

                    // Detect salient regions (main subjects)
                    let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()

                    // Classify scene
                    let classifyRequest = VNClassifyImageRequest()

                    // Detect objects
                    let objectRequest = VNRecognizeAnimalsRequest()

                    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                    try handler.perform([faceRequest, saliencyRequest, classifyRequest, objectRequest])

                    let analysis = ImageAnalysis(
                        faces: self.extractFaces(from: faceRequest),
                        saliencyRegion: self.extractSaliency(from: saliencyRequest),
                        sceneClassification: self.extractClassification(from: classifyRequest),
                        detectedObjects: self.extractObjects(from: objectRequest),
                        imageSize: CGSize(width: cgImage.width, height: cgImage.height)
                    )

                    continuation.resume(returning: analysis)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Intelligent Cropping

    private func cropToSubject(_ image: UIImage, analysis: ImageAnalysis) throws -> UIImage {
        guard let cgImage = image.cgImage else {
            throw EnhancementError.invalidImage
        }

        // Determine optimal crop region based on analysis
        let cropRect = calculateOptimalCrop(analysis: analysis, imageSize: analysis.imageSize)

        // Apply crop
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return image // Return original if crop fails
        }

        let croppedImage = UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)

        print("✂️ Intelligent crop applied: \(cropRect)")
        return croppedImage
    }

    private func calculateOptimalCrop(analysis: ImageAnalysis, imageSize: CGSize) -> CGRect {
        var cropRect = CGRect(origin: .zero, size: imageSize)

        // Priority 1: Center on faces if detected
        if let faceRect = analysis.faces.first {
            cropRect = expandedRect(around: faceRect, imageSize: imageSize, expansionFactor: 1.5)
        }
        // Priority 2: Center on salient region
        else if let saliencyRect = analysis.saliencyRegion {
            cropRect = expandedRect(around: saliencyRect, imageSize: imageSize, expansionFactor: 1.3)
        }
        // Priority 3: Apply rule of thirds crop
        else {
            cropRect = applyRuleOfThirds(imageSize: imageSize)
        }

        // Ensure crop is within bounds
        cropRect = cropRect.intersection(CGRect(origin: .zero, size: imageSize))

        return cropRect
    }

    private func expandedRect(around rect: CGRect, imageSize: CGSize, expansionFactor: CGFloat) -> CGRect {
        let expandedWidth = rect.width * expansionFactor
        let expandedHeight = rect.height * expansionFactor

        let x = max(0, rect.midX - expandedWidth / 2)
        let y = max(0, rect.midY - expandedHeight / 2)
        let width = min(expandedWidth, imageSize.width - x)
        let height = min(expandedHeight, imageSize.height - y)

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func applyRuleOfThirds(imageSize: CGSize) -> CGRect {
        // Center crop with 90% of original size, following rule of thirds
        let cropFactor: CGFloat = 0.9
        let newWidth = imageSize.width * cropFactor
        let newHeight = imageSize.height * cropFactor
        let x = (imageSize.width - newWidth) / 2
        let y = (imageSize.height - newHeight) / 2

        return CGRect(x: x, y: y, width: newWidth, height: newHeight)
    }

    // MARK: - Intelligent Editing

    private func applyIntelligentEdits(_ image: UIImage, analysis: ImageAnalysis) async throws -> UIImage {
        guard let cgImage = image.cgImage else {
            throw EnhancementError.invalidImage
        }

        var ciImage = CIImage(cgImage: cgImage)

        // 1. Auto exposure and tone adjustment
        ciImage = applyAutoTone(ciImage)

        // 2. Color balance based on scene
        ciImage = applyColorBalance(ciImage, sceneType: analysis.sceneClassification)

        // 3. Sharpen details
        ciImage = applySharpen(ciImage)

        // 4. Reduce noise
        ciImage = applyNoiseReduction(ciImage)

        // 5. Enhance contrast
        ciImage = applyContrastEnhancement(ciImage)

        // Render final image
        guard let outputCGImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            throw EnhancementError.renderingFailed
        }

        return UIImage(cgImage: outputCGImage, scale: image.scale, orientation: image.imageOrientation)
    }

    private func applyAutoTone(_ image: CIImage) -> CIImage {
        let filters = image.autoAdjustmentFilters(options: [
            .enhance: true,
            .redEye: false
        ])

        var result = image
        for filter in filters {
            filter.setValue(result, forKey: kCIInputImageKey)
            if let output = filter.outputImage {
                result = output
            }
        }

        return result
    }

    private func applyColorBalance(_ image: CIImage, sceneType: String?) -> CIImage {
        guard let filter = CIFilter(name: "CIColorControls") else { return image }

        filter.setValue(image, forKey: kCIInputImageKey)

        // Adjust based on scene type
        if let scene = sceneType?.lowercased() {
            if scene.contains("outdoor") || scene.contains("landscape") {
                // Enhance outdoor scenes
                filter.setValue(1.1, forKey: kCIInputSaturationKey) // Vibrant colors
                filter.setValue(0.05, forKey: kCIInputBrightnessKey) // Slightly brighter
            } else if scene.contains("indoor") || scene.contains("portrait") {
                // Warm indoor scenes
                filter.setValue(1.05, forKey: kCIInputSaturationKey)
                filter.setValue(0.02, forKey: kCIInputBrightnessKey)
            }
        } else {
            // Default balanced enhancement
            filter.setValue(1.08, forKey: kCIInputSaturationKey)
            filter.setValue(0.03, forKey: kCIInputBrightnessKey)
        }

        filter.setValue(1.05, forKey: kCIInputContrastKey)

        return filter.outputImage ?? image
    }

    private func applySharpen(_ image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CISharpenLuminance") else { return image }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(0.4, forKey: kCIInputSharpnessKey) // Moderate sharpening
        filter.setValue(0.5, forKey: kCIInputRadiusKey)

        return filter.outputImage ?? image
    }

    private func applyNoiseReduction(_ image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CINoiseReduction") else { return image }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(0.02, forKey: "inputNoiseLevel")
        filter.setValue(0.4, forKey: kCIInputSharpnessKey)

        return filter.outputImage ?? image
    }

    private func applyContrastEnhancement(_ image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CIVibrance") else { return image }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(0.3, forKey: "inputAmount") // Subtle vibrance boost

        return filter.outputImage ?? image
    }

    // MARK: - Export Optimization

    private func optimizeForExport(_ image: UIImage) throws -> UIImage {
        // Ensure optimal resolution (not too large, not too small)
        let targetMaxDimension: CGFloat = 2048
        let resized = resizeIfNeeded(image, maxDimension: targetMaxDimension)

        return resized
    }

    private func resizeIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxCurrentDimension = max(size.width, size.height)

        guard maxCurrentDimension > maxDimension else {
            return image // No resize needed
        }

        let scale = maxDimension / maxCurrentDimension
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, false, image.scale)
        defer { UIGraphicsEndImageContext() }

        image.draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }

    // MARK: - Helper Methods

    private func extractFaces(from request: VNDetectFaceRectanglesRequest) -> [CGRect] {
        guard let results = request.results else { return [] }
        return results.map { $0.boundingBox }
    }

    private func extractSaliency(from request: VNGenerateAttentionBasedSaliencyImageRequest) -> CGRect? {
        guard let result = request.results?.first,
              let salientObjects = result.salientObjects?.first else {
            return nil
        }
        return salientObjects.boundingBox
    }

    private func extractClassification(from request: VNClassifyImageRequest) -> String? {
        guard let result = request.results?.first else { return nil }
        return result.identifier
    }

    private func extractObjects(from request: VNRecognizeAnimalsRequest) -> [String] {
        guard let results = request.results else { return [] }
        return results.compactMap { $0.labels.first?.identifier }
    }
}

// MARK: - Supporting Types

public struct EnhancedImage {
    public let original: UIImage
    public let enhanced: UIImage
    public let analysis: ImageAnalysis
    public let improvements: [String]
}

public struct ImageAnalysis {
    public let faces: [CGRect]
    public let saliencyRegion: CGRect?
    public let sceneClassification: String?
    public let detectedObjects: [String]
    public let imageSize: CGSize
}

public enum EnhancementError: LocalizedError {
    case invalidImage
    case renderingFailed
    case noSubjectDetected

    public var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Invalid image format"
        case .renderingFailed:
            return "Failed to render enhanced image"
        case .noSubjectDetected:
            return "No subject detected for cropping"
        }
    }
}
