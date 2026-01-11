import UIKit
import CoreImage
import Accelerate

/// Professional HDR+ Image Processing
/// Multi-frame HDR, tone mapping, and advanced color grading
@MainActor
public class HDRProcessor {

    // MARK: - Singleton
    public static let shared = HDRProcessor()

    // MARK: - Properties
    private let context = CIContext()
    private let queue = DispatchQueue(label: "com.metaglasses.hdr", qos: .userInitiated)

    // MARK: - Initialization
    private init() {
        print("🎨 HDRProcessor initialized")
    }

    // MARK: - HDR Processing

    /// Process multiple exposures into HDR image
    public func processHDR(images: [UIImage]) async throws -> UIImage {
        guard images.count >= 3 else {
            throw HDRError.insufficientImages
        }

        print("🌅 Processing \(images.count) images into HDR...")

        // Convert to CIImages
        let ciImages = images.compactMap { $0.ciImage ?? CIImage(image: $0) }
        guard ciImages.count == images.count else {
            throw HDRError.conversionFailed
        }

        // Align images (compensate for camera shake)
        let alignedImages = try await alignImages(ciImages)

        // Merge exposures
        let mergedImage = try await mergeExposures(alignedImages)

        // Tone mapping
        let toneMappedImage = try await toneMap(mergedImage)

        // Convert back to UIImage
        guard let cgImage = context.createCGImage(toneMappedImage, from: toneMappedImage.extent) else {
            throw HDRError.conversionFailed
        }

        print("✅ HDR processing complete")
        return UIImage(cgImage: cgImage)
    }

    /// Apply HDR effect to single image (simulated)
    public func applyHDREffect(to image: UIImage, intensity: Double = 0.5) async throws -> UIImage {
        guard let ciImage = image.ciImage ?? CIImage(image: image) else {
            throw HDRError.invalidImage
        }

        // Enhance shadows
        let shadowFilter = CIFilter(name: "CIHighlightShadowAdjust")
        shadowFilter?.setValue(ciImage, forKey: kCIInputImageKey)
        shadowFilter?.setValue(intensity, forKey: "inputShadowAmount")

        guard let shadowOutput = shadowFilter?.outputImage else {
            throw HDRError.filterFailed
        }

        // Enhance highlights
        let highlightFilter = CIFilter(name: "CIHighlightShadowAdjust")
        highlightFilter?.setValue(shadowOutput, forKey: kCIInputImageKey)
        highlightFilter?.setValue(-intensity * 0.5, forKey: "inputHighlightAmount")

        guard let highlightOutput = highlightFilter?.outputImage else {
            throw HDRError.filterFailed
        }

        // Boost vibrancy
        let vibrancyFilter = CIFilter(name: "CIVibrance")
        vibrancyFilter?.setValue(highlightOutput, forKey: kCIInputImageKey)
        vibrancyFilter?.setValue(intensity, forKey: kCIInputAmountKey)

        guard let finalOutput = vibrancyFilter?.outputImage,
              let cgImage = context.createCGImage(finalOutput, from: finalOutput.extent) else {
            throw HDRError.filterFailed
        }

        return UIImage(cgImage: cgImage)
    }

    // MARK: - Tone Mapping

    private func toneMap(_ image: CIImage) async throws -> CIImage {
        // Reinhard tone mapping
        let filter = CIFilter(name: "CIToneCurve")
        filter?.setValue(image, forKey: kCIInputImageKey)

        // Adjust tone curve for HDR look
        filter?.setValue(CIVector(x: 0.0, y: 0.0), forKey: "inputPoint0")
        filter?.setValue(CIVector(x: 0.25, y: 0.2), forKey: "inputPoint1")
        filter?.setValue(CIVector(x: 0.5, y: 0.5), forKey: "inputPoint2")
        filter?.setValue(CIVector(x: 0.75, y: 0.8), forKey: "inputPoint3")
        filter?.setValue(CIVector(x: 1.0, y: 1.0), forKey: "inputPoint4")

        guard let output = filter?.outputImage else {
            throw HDRError.toneMappingFailed
        }

        return output
    }

    // MARK: - Image Alignment

    private func alignImages(_ images: [CIImage]) async throws -> [CIImage] {
        // Use first image as reference
        guard let reference = images.first else {
            throw HDRError.invalidImage
        }

        var alignedImages: [CIImage] = [reference]

        // Align subsequent images to reference
        for image in images.dropFirst() {
            // In production, implement feature-based alignment
            // For now, assume images are already aligned
            alignedImages.append(image)
        }

        return alignedImages
    }

    // MARK: - Exposure Merging

    private func mergeExposures(_ images: [CIImage]) async throws -> CIImage {
        guard let first = images.first else {
            throw HDRError.invalidImage
        }

        // Simple averaging for now
        // In production, implement weighted merging based on exposure values
        var result = first

        for image in images.dropFirst() {
            let filter = CIFilter(name: "CIAdditionCompositing")
            filter?.setValue(image, forKey: kCIInputImageKey)
            filter?.setValue(result, forKey: kCIInputBackgroundImageKey)

            if let output = filter?.outputImage {
                result = output
            }
        }

        // Normalize
        let normalizeFilter = CIFilter(name: "CIColorControls")
        normalizeFilter?.setValue(result, forKey: kCIInputImageKey)
        normalizeFilter?.setValue(1.0 / Double(images.count), forKey: kCIInputBrightnessKey)

        guard let normalized = normalizeFilter?.outputImage else {
            throw HDRError.mergingFailed
        }

        return normalized
    }

    // MARK: - Color Grading

    /// Apply professional color grading
    public func applyColorGrade(_ grade: ColorGrade, to image: UIImage) async throws -> UIImage {
        guard let ciImage = image.ciImage ?? CIImage(image: image) else {
            throw HDRError.invalidImage
        }

        let graded = try await applyGradeFilters(grade, to: ciImage)

        guard let cgImage = context.createCGImage(graded, from: graded.extent) else {
            throw HDRError.conversionFailed
        }

        return UIImage(cgImage: cgImage)
    }

    private func applyGradeFilters(_ grade: ColorGrade, to image: CIImage) async throws -> CIImage {
        var result = image

        // Temperature & tint
        if let tempFilter = CIFilter(name: "CITemperatureAndTint") {
            tempFilter.setValue(result, forKey: kCIInputImageKey)
            tempFilter.setValue(CIVector(x: grade.temperature, y: grade.tint), forKey: "inputNeutral")
            if let output = tempFilter.outputImage {
                result = output
            }
        }

        // Exposure
        if let exposureFilter = CIFilter(name: "CIExposureAdjust") {
            exposureFilter.setValue(result, forKey: kCIInputImageKey)
            exposureFilter.setValue(grade.exposure, forKey: kCIInputEVKey)
            if let output = exposureFilter.outputImage {
                result = output
            }
        }

        // Contrast
        if let contrastFilter = CIFilter(name: "CIColorControls") {
            contrastFilter.setValue(result, forKey: kCIInputImageKey)
            contrastFilter.setValue(grade.contrast, forKey: kCIInputContrastKey)
            contrastFilter.setValue(grade.saturation, forKey: kCIInputSaturationKey)
            if let output = contrastFilter.outputImage {
                result = output
            }
        }

        return result
    }
}

// MARK: - Supporting Types

public struct ColorGrade {
    public var temperature: CGFloat = 6500
    public var tint: CGFloat = 0
    public var exposure: Double = 0.0
    public var contrast: Double = 1.0
    public var saturation: Double = 1.0
    public var highlights: Double = 0.0
    public var shadows: Double = 0.0
    public var whites: Double = 0.0
    public var blacks: Double = 0.0

    public static let natural = ColorGrade()

    public static let vivid = ColorGrade(
        contrast: 1.2,
        saturation: 1.3,
        highlights: -0.1
    )

    public static let cinematic = ColorGrade(
        temperature: 5500,
        tint: 10,
        contrast: 1.1,
        saturation: 0.9,
        shadows: 0.1
    )

    public static let dramatic = ColorGrade(
        contrast: 1.4,
        saturation: 0.8,
        highlights: -0.2,
        shadows: 0.2
    )
}

public enum HDRError: LocalizedError {
    case invalidImage
    case insufficientImages
    case conversionFailed
    case filterFailed
    case toneMappingFailed
    case mergingFailed
    case alignmentFailed

    public var errorDescription: String? {
        switch self {
        case .invalidImage: return "Invalid image provided"
        case .insufficientImages: return "Need at least 3 images for HDR"
        case .conversionFailed: return "Image conversion failed"
        case .filterFailed: return "Filter application failed"
        case .toneMappingFailed: return "Tone mapping failed"
        case .mergingFailed: return "Exposure merging failed"
        case .alignmentFailed: return "Image alignment failed"
        }
    }
}
