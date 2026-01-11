import Foundation
import UIKit
import Vision

public class AIVisionAnalyzer {
    public static let shared = AIVisionAnalyzer()
    
    private init() {}
    
    public struct SceneAnalysis {
        public let faces: [FaceAnalysis]
        public let objects: [ObjectDetection]
        public let text: [TextRecognition]
        public let sceneClassification: String
        public let timestamp: Date
        
        public init(faces: [FaceAnalysis], objects: [ObjectDetection], text: [TextRecognition], sceneClassification: String, timestamp: Date) {
            self.faces = faces
            self.objects = objects
            self.text = text
            self.sceneClassification = sceneClassification
            self.timestamp = timestamp
        }
    }
    
    public struct FaceAnalysis {
        public let boundingBox: CGRect
        public let confidence: Float
        public let landmarks: [String: CGPoint]
        
        public init(boundingBox: CGRect, confidence: Float, landmarks: [String : CGPoint]) {
            self.boundingBox = boundingBox
            self.confidence = confidence
            self.landmarks = landmarks
        }
    }
    
    public struct ObjectDetection {
        public let label: String
        public let confidence: Float
        public let boundingBox: CGRect
        
        public init(label: String, confidence: Float, boundingBox: CGRect) {
            self.label = label
            self.confidence = confidence
            self.boundingBox = boundingBox
        }
    }
    
    public struct TextRecognition {
        public let text: String
        public let confidence: Float
        public let boundingBox: CGRect
        
        public init(text: String, confidence: Float, boundingBox: CGRect) {
            self.text = text
            self.confidence = confidence
            self.boundingBox = boundingBox
        }
    }
    
    public func analyzeScene(in stereoPair: StereoPair) async throws -> SceneAnalysis {
        async let faces = detectFaces(in: stereoPair.leftImage)
        async let text = recognizeText(in: stereoPair.leftImage)
        async let scene = classifyScene(in: stereoPair.leftImage)
        
        let faceResults = try await faces
        let textResults = try await text
        let sceneResult = try await scene
        
        // Simplified object detection (using scene classification as proxy)
        let objects = [ObjectDetection(label: sceneResult, confidence: 0.8, boundingBox: .zero)]
        
        return SceneAnalysis(
            faces: faceResults,
            objects: objects,
            text: textResults,
            sceneClassification: sceneResult,
            timestamp: Date()
        )
    }
    
    private func detectFaces(in image: UIImage) async throws -> [FaceAnalysis] {
        guard let cgImage = image.cgImage else { return [] }
        
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        try handler.perform([request])
        
        guard let results = request.results else { return [] }
        
        return results.map { observation in
            FaceAnalysis(
                boundingBox: observation.boundingBox,
                confidence: observation.confidence,
                landmarks: [:]
            )
        }
    }
    
    private func recognizeText(in image: UIImage) async throws -> [TextRecognition] {
        guard let cgImage = image.cgImage else { return [] }
        
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        
        guard let results = request.results else { return [] }
        
        return results.compactMap { observation in
            guard let text = observation.topCandidates(1).first else { return nil }
            return TextRecognition(
                text: text.string,
                confidence: observation.confidence,
                boundingBox: observation.boundingBox
            )
        }
    }
    
    private func classifyScene(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { return "Unknown" }
        
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        try handler.perform([request])
        
        guard let results = request.results,
              let topResult = results.first else {
            return "Unknown"
        }
        
        return topResult.identifier
    }
}
