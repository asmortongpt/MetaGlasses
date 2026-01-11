import UIKit
import Vision
import CoreML
import CoreImage

/// Advanced Scene Segmentation - Segment everything in the image
/// Provides pixel-perfect masks for people, objects, backgrounds
@MainActor
public class SceneSegmentation {

    // MARK: - Singleton
    public static let shared = SceneSegmentation()

    // MARK: - Properties
    private let queue = DispatchQueue(label: "com.metaglasses.segmentation", qos: .userInitiated)
    private let context = CIContext()

    // MARK: - Initialization
    private init() {
        print("🎨 SceneSegmentation initialized - Ready to segment scenes")
    }

    // MARK: - Person Segmentation

    /// Generate precise person segmentation mask
    public func segmentPerson(in image: UIImage) async throws -> SegmentationResult {
        guard let cgImage = image.cgImage else {
            throw SegmentationError.invalidImage
        }

        print("👤 Segmenting person from background...")

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNGeneratePersonSegmentationRequest()
            request.qualityLevel = .accurate
            request.outputPixelFormat = kCVPixelFormatType_OneComponent8

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            queue.async {
                do {
                    try handler.perform([request])

                    guard let result = request.results?.first else {
                        throw SegmentationError.segmentationFailed
                    }

                    let mask = try self.convertToUIImage(pixelBuffer: result.pixelBuffer)

                    let segmentation = SegmentationResult(
                        originalImage: image,
                        mask: mask,
                        confidence: result.confidence,
                        type: .person
                    )

                    print("✅ Person segmentation complete")
                    continuation.resume(returning: segmentation)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Remove background - create transparent PNG with just the person
    public func removeBackground(from image: UIImage) async throws -> UIImage {
        let segmentation = try await segmentPerson(in: image)

        guard let originalCG = image.cgImage,
              let maskCG = segmentation.mask.cgImage else {
            throw SegmentationError.invalidImage
        }

        // Create transparent background image
        let ciImage = CIImage(cgImage: originalCG)
        let maskImage = CIImage(cgImage: maskCG)

        // Apply mask
        let filter = CIFilter(name: "CIBlendWithMask")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(maskImage, forKey: kCIInputMaskImageKey)

        guard let outputImage = filter?.outputImage,
              let cgOutput = context.createCGImage(outputImage, from: outputImage.extent) else {
            throw SegmentationError.maskingFailed
        }

        print("✂️ Background removed successfully")
        return UIImage(cgImage: cgOutput)
    }

    /// Blur background while keeping subject sharp
    public func blurBackground(in image: UIImage, intensity: Double = 20.0) async throws -> UIImage {
        let segmentation = try await segmentPerson(in: image)

        guard let originalCG = image.cgImage,
              let maskCG = segmentation.mask.cgImage else {
            throw SegmentationError.invalidImage
        }

        let ciImage = CIImage(cgImage: originalCG)
        let maskImage = CIImage(cgImage: maskCG)

        // Create blurred background
        let blurFilter = CIFilter(name: "CIGaussianBlur")
        blurFilter?.setValue(ciImage, forKey: kCIInputImageKey)
        blurFilter?.setValue(intensity, forKey: kCIInputRadiusKey)

        guard let blurredImage = blurFilter?.outputImage else {
            throw SegmentationError.blurFailed
        }

        // Blend original with blurred using mask
        let blendFilter = CIFilter(name: "CIBlendWithMask")
        blendFilter?.setValue(ciImage, forKey: kCIInputImageKey)
        blendFilter?.setValue(blurredImage, forKey: kCIInputBackgroundImageKey)
        blendFilter?.setValue(maskImage, forKey: kCIInputMaskImageKey)

        guard let outputImage = blendFilter?.outputImage,
              let cgOutput = context.createCGImage(outputImage, from: outputImage.extent) else {
            throw SegmentationError.blendFailed
        }

        print("🌫️ Background blurred - Portrait mode effect applied")
        return UIImage(cgImage: cgOutput)
    }

    // MARK: - Advanced Segmentation

    /// Segment multiple regions in the image
    public func segmentAllRegions(in image: UIImage) async throws -> [RegionSegment] {
        // Detect saliency - what are the interesting regions?
        guard let cgImage = image.cgImage else {
            throw SegmentationError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNGenerateAttentionBasedSaliencyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            queue.async {
                do {
                    try handler.perform([request])

                    var regions: [RegionSegment] = []

                    if let results = request.results {
                        for result in results {
                            if let salientObjects = result.salientObjects {
                                for object in salientObjects {
                                    regions.append(RegionSegment(
                                        boundingBox: object.boundingBox,
                                        confidence: result.confidence,
                                        type: .salient
                                    ))
                                }
                            }
                        }
                    }

                    print("📍 Segmented \(regions.count) salient regions")
                    continuation.resume(returning: regions)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Replace background with custom image or color
    public func replaceBackground(in image: UIImage, with background: UIImage) async throws -> UIImage {
        let segmentation = try await segmentPerson(in: image)

        guard let originalCG = image.cgImage,
              let maskCG = segmentation.mask.cgImage,
              let backgroundCG = background.cgImage else {
            throw SegmentationError.invalidImage
        }

        let ciOriginal = CIImage(cgImage: originalCG)
        let ciMask = CIImage(cgImage: maskCG)
        let ciBackground = CIImage(cgImage: backgroundCG)

        // Scale background to match original
        let scaleX = ciOriginal.extent.width / ciBackground.extent.width
        let scaleY = ciOriginal.extent.height / ciBackground.extent.height
        let scaledBackground = ciBackground.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Blend with mask
        let blendFilter = CIFilter(name: "CIBlendWithMask")
        blendFilter?.setValue(ciOriginal, forKey: kCIInputImageKey)
        blendFilter?.setValue(scaledBackground, forKey: kCIInputBackgroundImageKey)
        blendFilter?.setValue(ciMask, forKey: kCIInputMaskImageKey)

        guard let outputImage = blendFilter?.outputImage,
              let cgOutput = context.createCGImage(outputImage, from: outputImage.extent) else {
            throw SegmentationError.blendFailed
        }

        print("🖼️ Background replaced successfully")
        return UIImage(cgImage: cgOutput)
    }

    /// Apply creative effects to background only
    public func applyBackgroundEffect(_ effect: BackgroundEffect, to image: UIImage) async throws -> UIImage {
        switch effect {
        case .blur(let intensity):
            return try await blurBackground(in: image, intensity: intensity)
        case .grayscale:
            return try await applyGrayscaleBackground(in: image)
        case .colorize(let color):
            return try await colorizeBackground(in: image, color: color)
        case .remove:
            return try await removeBackground(from: image)
        }
    }

    private func applyGrayscaleBackground(in image: UIImage) async throws -> UIImage {
        let segmentation = try await segmentPerson(in: image)

        guard let originalCG = image.cgImage,
              let maskCG = segmentation.mask.cgImage else {
            throw SegmentationError.invalidImage
        }

        let ciImage = CIImage(cgImage: originalCG)
        let maskImage = CIImage(cgImage: maskCG)

        // Convert to grayscale
        let grayscaleFilter = CIFilter(name: "CIPhotoEffectMono")
        grayscaleFilter?.setValue(ciImage, forKey: kCIInputImageKey)

        guard let grayscaleImage = grayscaleFilter?.outputImage else {
            throw SegmentationError.effectFailed
        }

        // Blend color subject with grayscale background
        let blendFilter = CIFilter(name: "CIBlendWithMask")
        blendFilter?.setValue(ciImage, forKey: kCIInputImageKey)
        blendFilter?.setValue(grayscaleImage, forKey: kCIInputBackgroundImageKey)
        blendFilter?.setValue(maskImage, forKey: kCIInputMaskImageKey)

        guard let outputImage = blendFilter?.outputImage,
              let cgOutput = context.createCGImage(outputImage, from: outputImage.extent) else {
            throw SegmentationError.blendFailed
        }

        return UIImage(cgImage: cgOutput)
    }

    private func colorizeBackground(in image: UIImage, color: UIColor) async throws -> UIImage {
        let segmentation = try await segmentPerson(in: image)

        guard let originalCG = image.cgImage,
              let maskCG = segmentation.mask.cgImage else {
            throw SegmentationError.invalidImage
        }

        let ciImage = CIImage(cgImage: originalCG)
        let maskImage = CIImage(cgImage: maskCG)

        // Create solid color background
        let colorFilter = CIFilter(name: "CIConstantColorGenerator")
        colorFilter?.setValue(CIColor(color: color), forKey: kCIInputColorKey)

        guard let colorImage = colorFilter?.outputImage else {
            throw SegmentationError.effectFailed
        }

        // Blend with mask
        let blendFilter = CIFilter(name: "CIBlendWithMask")
        blendFilter?.setValue(ciImage, forKey: kCIInputImageKey)
        blendFilter?.setValue(colorImage, forKey: kCIInputBackgroundImageKey)
        blendFilter?.setValue(maskImage, forKey: kCIInputMaskImageKey)

        guard let outputImage = blendFilter?.outputImage,
              let cgOutput = context.createCGImage(outputImage, from: outputImage.extent) else {
            throw SegmentationError.blendFailed
        }

        return UIImage(cgImage: cgOutput)
    }

    // MARK: - Helpers

    private func convertToUIImage(pixelBuffer: CVPixelBuffer) throws -> UIImage {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw SegmentationError.conversionFailed
        }

        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Supporting Types

public struct SegmentationResult {
    public let originalImage: UIImage
    public let mask: UIImage
    public let confidence: Double
    public let type: SegmentationType
}

public struct RegionSegment {
    public let boundingBox: CGRect
    public let confidence: Double
    public let type: RegionType
}

public enum SegmentationType {
    case person
    case object
    case background
    case salient
}

public enum RegionType {
    case salient
    case object
    case text
    case face
}

public enum BackgroundEffect {
    case blur(intensity: Double)
    case grayscale
    case colorize(UIColor)
    case remove
}

public enum SegmentationError: LocalizedError {
    case invalidImage
    case segmentationFailed
    case maskingFailed
    case blurFailed
    case blendFailed
    case effectFailed
    case conversionFailed

    public var errorDescription: String? {
        switch self {
        case .invalidImage: return "Invalid image provided"
        case .segmentationFailed: return "Scene segmentation failed"
        case .maskingFailed: return "Mask application failed"
        case .blurFailed: return "Blur effect failed"
        case .blendFailed: return "Image blending failed"
        case .effectFailed: return "Effect application failed"
        case .conversionFailed: return "Image conversion failed"
        }
    }
}
