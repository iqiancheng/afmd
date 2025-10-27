import Foundation
import Vision
import CoreML
import Combine
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Vision Service Manager

/// Manager for vision-related services including OCR, object detection, and image analysis
@MainActor
class VisionServiceManager: ObservableObject {
    static let shared = VisionServiceManager()
    
    private init() {}
    
    // MARK: - OCR (Optical Character Recognition)
    
    /// Extract text from image data using Vision framework
    func extractText(from imageData: Data) async throws -> OCRResult {
        #if canImport(UIKit)
        guard let image = UIImage(data: imageData) else {
            throw VisionError.invalidImageData
        }
        return try await extractText(from: image)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: imageData) else {
            throw VisionError.invalidImageData
        }
        return try await extractText(from: image)
        #else
        throw VisionError.unsupportedPlatform
        #endif
    }
    
    #if canImport(UIKit)
    private func extractText(from image: UIImage) async throws -> OCRResult {
        guard let cgImage = image.cgImage else {
            throw VisionError.invalidImageData
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: VisionError.noTextFound)
                    return
                }
                
                let recognizedStrings = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }
                
                let fullText = recognizedStrings.joined(separator: " ")
                let confidence = observations.compactMap { $0.topCandidates(1).first?.confidence }.reduce(0, +) / Float(observations.count)
                
                // Detect language
                let language = self.detectLanguageInText(fullText)
                
                let result = OCRResult(
                    text: fullText,
                    confidence: confidence,
                    language: language
                )
                
                continuation.resume(returning: result)
            }
            
            // Configure for better accuracy
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    #elseif canImport(AppKit)
    private func extractText(from image: NSImage) async throws -> OCRResult {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw VisionError.invalidImageData
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: VisionError.noTextFound)
                    return
                }
                
                let recognizedStrings = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }
                
                let fullText = recognizedStrings.joined(separator: " ")
                let confidence = observations.compactMap { $0.topCandidates(1).first?.confidence }.reduce(0, +) / Float(observations.count)
                
                // Detect language
                let language = self.detectLanguageInText(fullText)
                
                let result = OCRResult(
                    text: fullText,
                    confidence: confidence,
                    language: language
                )
                
                continuation.resume(returning: result)
            }
            
            // Configure for better accuracy
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    #endif
    
    // MARK: - Object Detection
    
    /// Detect objects in image data
    func detectObjects(in imageData: Data) async throws -> [DetectedObject] {
        #if canImport(UIKit)
        guard let image = UIImage(data: imageData) else {
            throw VisionError.invalidImageData
        }
        return try await detectObjects(in: image)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: imageData) else {
            throw VisionError.invalidImageData
        }
        return try await detectObjects(in: image)
        #else
        throw VisionError.unsupportedPlatform
        #endif
    }
    
    #if canImport(UIKit)
    private func detectObjects(in image: UIImage) async throws -> [DetectedObject] {
        guard let cgImage = image.cgImage else {
            throw VisionError.invalidImageData
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNClassifyImageRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                let objects = observations.compactMap { observation -> DetectedObject? in
                    // Only include observations with confidence > 0.1
                    guard observation.confidence > 0.1 else { return nil }
                    
                    return DetectedObject(
                        label: observation.identifier,
                        confidence: observation.confidence,
                        boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1), // VNClassifyImageRequest doesn't provide bounding boxes
                        description: "\(observation.identifier) with \(Int(observation.confidence * 100))% confidence"
                    )
                }
                
                continuation.resume(returning: objects)
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    #elseif canImport(AppKit)
    private func detectObjects(in image: NSImage) async throws -> [DetectedObject] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw VisionError.invalidImageData
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNClassifyImageRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                let objects = observations.compactMap { observation -> DetectedObject? in
                    // Only include observations with confidence > 0.1
                    guard observation.confidence > 0.1 else { return nil }
                    
                    return DetectedObject(
                        label: observation.identifier,
                        confidence: observation.confidence,
                        boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1), // VNClassifyImageRequest doesn't provide bounding boxes
                        description: "\(observation.identifier) with \(Int(observation.confidence * 100))% confidence"
                    )
                }
                
                continuation.resume(returning: objects)
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    #endif
    
    // MARK: - Comprehensive Image Analysis
    
    /// Analyze image with OCR, object detection, and description
    func analyzeImage(_ imageData: Data) async throws -> ImageAnalysisResult {
        #if canImport(UIKit)
        guard let image = UIImage(data: imageData) else {
            throw VisionError.invalidImageData
        }
        return try await analyzeImage(image)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: imageData) else {
            throw VisionError.invalidImageData
        }
        return try await analyzeImage(image)
        #else
        throw VisionError.unsupportedPlatform
        #endif
    }
    
    #if canImport(UIKit)
    func analyzeImage(_ image: UIImage) async throws -> ImageAnalysisResult {
        let startTime = Date()
        
        // Perform OCR and object detection concurrently
        async let ocrResult = extractText(from: image)
        async let objects = detectObjects(in: image)
        
        let (textResult, detectedObjects) = try await (ocrResult, objects)
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        // Create image description based on analysis
        var description = "Image analysis completed. "
        if !textResult.text.isEmpty {
            description += "Contains text: \"\(textResult.text.prefix(100))\(textResult.text.count > 100 ? "..." : "")\". "
        }
        if !detectedObjects.isEmpty {
            let objectLabels = detectedObjects.map { $0.label }
            description += "Objects detected: \(objectLabels.joined(separator: ", ")). "
        }
        description += "Analysis confidence: \(Int(textResult.confidence * 100))%."
        
        return ImageAnalysisResult(
            textContent: textResult.text,
            objectDetections: detectedObjects,
            imageDescription: description,
            confidence: textResult.confidence,
            processingTime: processingTime
        )
    }
    #elseif canImport(AppKit)
    func analyzeImage(_ image: NSImage) async throws -> ImageAnalysisResult {
        let startTime = Date()
        
        // Perform OCR and object detection concurrently
        async let ocrResult = extractText(from: image)
        async let objects = detectObjects(in: image)
        
        let (textResult, detectedObjects) = try await (ocrResult, objects)
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        // Create image description based on analysis
        var description = "Image analysis completed. "
        if !textResult.text.isEmpty {
            description += "Contains text: \"\(textResult.text.prefix(100))\(textResult.text.count > 100 ? "..." : "")\". "
        }
        if !detectedObjects.isEmpty {
            let objectLabels = detectedObjects.map { $0.label }
            description += "Objects detected: \(objectLabels.joined(separator: ", ")). "
        }
        description += "Analysis confidence: \(Int(textResult.confidence * 100))%."
        
        return ImageAnalysisResult(
            textContent: textResult.text,
            objectDetections: detectedObjects,
            imageDescription: description,
            confidence: textResult.confidence,
            processingTime: processingTime
        )
    }
    #endif
    
    // MARK: - Language Detection
    
    /// Detect language in text using NSLinguisticTagger
    func detectLanguageInText(_ text: String) -> String? {
        let tagger = NSLinguisticTagger(tagSchemes: [.language], options: 0)
        tagger.string = text
        
        let range = NSRange(location: 0, length: text.utf16.count)
        return tagger.dominantLanguage
    }
}

// MARK: - Data Models

struct OCRResult {
    let text: String
    let confidence: Float
    let language: String?
}

struct DetectedObject {
    let label: String
    let confidence: Float
    let boundingBox: CGRect
    let description: String
}

struct ImageAnalysisResult {
    let textContent: String
    let objectDetections: [DetectedObject]
    let imageDescription: String
    let confidence: Float
    let processingTime: TimeInterval
}

// MARK: - Error Types

enum VisionError: Error, LocalizedError {
    case invalidImageData
    case noTextFound
    case unsupportedPlatform
    
    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "Invalid image data provided"
        case .noTextFound:
            return "No text found in image"
        case .unsupportedPlatform:
            return "Vision processing not supported on this platform"
        }
    }
}