import Foundation
import FoundationModels
import Vapor
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Apple Intelligence Manager

/// Manager for Apple Intelligence on-device language model
actor OnDeviceModelManager {
    private let model: SystemLanguageModel

    init() {
        self.model = SystemLanguageModel.default
    }

    /// Check if the model is available
    func isModelAvailable() -> (available: Bool, reason: String?) {
        let availability = model.availability

        switch availability {
        case .available:
            return (true, nil)

        case .unavailable(let reason):
            let reasonString: String
            switch reason {
            case .deviceNotEligible:
                reasonString =
                    "Device not eligible for Apple Intelligence. Supported devices: iPhone 15 Pro/Pro Max or newer, iPad with M1 chip or newer, Mac with Apple Silicon"

            case .appleIntelligenceNotEnabled:
                reasonString =
                    "Apple Intelligence not enabled. Enable it in Settings > Apple Intelligence & Siri"

            case .modelNotReady:
                reasonString =
                    "AI model not ready. Models are downloaded automatically based on network status, battery level, and system load. Please wait and try again later."

            @unknown default:
                reasonString = "Unknown availability issue"
            }
            return (false, reasonString)

        @unknown default:
            return (false, "Unknown availability status")
        }
    }

    /// Get supported languages
    func getSupportedLanguages() -> [String] {
        let languages = model.supportedLanguages

        return languages.compactMap { language -> String? in
            let locale = Locale(identifier: language.maximalIdentifier)

            // Get the display name in the current locale
            if let displayName = locale.localizedString(forIdentifier: language.maximalIdentifier) {
                return displayName
            }

            // Fallback to language code if display name is not available
            return language.languageCode?.identifier
        }.sorted()
    }
    
    /// Get supported language codes
    func getSupportedLanguageCodes() -> [String] {
        let languages = model.supportedLanguages
        let codes = languages.compactMap { language in
            language.languageCode?.identifier
        }
        print("DEBUG: Supported language codes: \(codes)")
        return codes
    }
    
    /// Detect language from text using NSLinguisticTagger
    func detectLanguage(from text: String) -> String? {
        let tagger = NSLinguisticTagger(tagSchemes: [.language], options: 0)
        tagger.string = text
        
        let range = NSRange(location: 0, length: text.utf16.count)
        let language = tagger.dominantLanguage
        
        print("DEBUG: Detected language: \(language ?? "nil") for text: \(text.prefix(50))...")
        
        return language
    }
    
    /// Check if a language is supported by the model
    func isLanguageSupported(_ languageCode: String) -> Bool {
        let supportedCodes = getSupportedLanguageCodes()
        return supportedCodes.contains(languageCode)
    }
    
    /// Validate text language before processing
    func validateLanguage(_ text: String) throws {
        guard let detectedLanguage = detectLanguage(from: text) else {
            // If we can't detect the language, proceed (might be mixed content)
            return
        }
        
        guard isLanguageSupported(detectedLanguage) else {
            let supportedLanguages = getSupportedLanguages()
            let supportedCodes = getSupportedLanguageCodes()
            
            throw Abort(
                .badRequest,
                reason: "Unsupported language '\(detectedLanguage)' detected. Supported languages: \(supportedLanguages.joined(separator: ", ")) (codes: \(supportedCodes.joined(separator: ", "))). Please use English or another supported language."
            )
        }
    }

    /// Convert chat messages to transcript entries
    func convertMessagesToTranscript(_ messages: [ChatMessage]) -> [Transcript.Entry] {
        var entries: [Transcript.Entry] = []

        print("DEBUG: Converting \(messages.count) messages to transcript")
        
        // Process all messages in order
        for (index, message) in messages.enumerated() {
            print("DEBUG: Message \(index): role=\(message.role), content=\(message.content.prefix(100))...")
            
            // Check language of each message
            if let detectedLang = detectLanguage(from: message.content) {
                print("DEBUG: Message \(index) language: \(detectedLang)")
            }
            
            let textSegment = Transcript.TextSegment(content: message.content)

            switch message.role.lowercased() {
            case "system":
                // Convert system messages to instructions
                let instructions = Transcript.Instructions(
                    segments: [.text(textSegment)],
                    toolDefinitions: []
                )
                entries.append(.instructions(instructions))

            case "user":
                // Convert user messages to prompts
                let prompt = Transcript.Prompt(
                    segments: [.text(textSegment)]
                )
                entries.append(.prompt(prompt))

            case "assistant":
                // Convert assistant messages to responses
                let response = Transcript.Response(
                    assetIDs: [],
                    segments: [.text(textSegment)]
                )
                entries.append(.response(response))

            default:
                // Treat unknown roles as user messages
                let prompt = Transcript.Prompt(
                    segments: [.text(textSegment)]
                )
                entries.append(.prompt(prompt))
            }
        }

        print("DEBUG: Created \(entries.count) transcript entries")
        return entries
    }

    /// Generate a response for the given messages with conversation context
    func generateResponse(
        for messages: [ChatMessage], temperature: Double? = nil, maxTokens: Int? = nil
    ) async throws -> String {
        // Check availability first
        let (available, reason) = isModelAvailable()
        guard available else {
            throw Abort(
                .serviceUnavailable, reason: reason ?? "Apple Intelligence model is not available")
        }

        guard !messages.isEmpty else {
            throw Abort(.badRequest, reason: "No messages provided")
        }

        // Get the last message as the current prompt
        let lastMessage = messages.last!
        let currentPrompt = lastMessage.content

        // Validate language before processing
        try validateLanguage(currentPrompt)

        // Convert previous messages (excluding the last one) to transcript
        let previousMessages = messages.count > 1 ? Array(messages.dropLast()) : []
        let transcriptEntries = convertMessagesToTranscript(previousMessages)

        // Create transcript with conversation history
        let transcript = Transcript(entries: transcriptEntries)

        // Create new session with the conversation transcript
        let session = LanguageModelSession(
            transcript: transcript
        )

        do {
            // Create generation options if temperature is specified
            var options = GenerationOptions()
            if let temp = temperature {
                options = GenerationOptions(temperature: temp, maximumResponseTokens: maxTokens)
            } else if let maxTokens = maxTokens {
                options = GenerationOptions(maximumResponseTokens: maxTokens)
            }

            // Generate response using the current prompt
            let response = try await session.respond(
                to: currentPrompt,
                options: options
            )

            let content = response.content
            return content
        } catch {
            // Handle specific FoundationModels errors
            if let foundationError = error as? FoundationModels.LanguageModelSession.GenerationError {
                switch foundationError {
                case .unsupportedLanguageOrLocale(let context):
                    let supportedLanguages = getSupportedLanguages()
                    let supportedCodes = getSupportedLanguageCodes()
                    throw Abort(
                        .badRequest,
                        reason: "Unsupported language detected. Supported languages: \(supportedLanguages.joined(separator: ", ")) (codes: \(supportedCodes.joined(separator: ", "))). Please use English or another supported language."
                    )
                default:
                    throw Abort(
                        .internalServerError,
                        reason: "Language model error: \(foundationError.localizedDescription)")
                }
            }
            
            throw Abort(
                .internalServerError,
                reason: "Error generating response: \(error.localizedDescription)")
        }
    }

    /// Generate a response for a single prompt (for backward compatibility)
    func generateResponse(for prompt: String, temperature: Double? = nil, maxTokens: Int? = nil)
        async throws -> String
    {
        let messages = [ChatMessage(role: "user", content: prompt)]
        return try await generateResponse(
            for: messages, temperature: temperature, maxTokens: maxTokens)
    }
    
    // MARK: - Multimodal Processing
    
    /// Process multimodal content (text + images) and generate response
    func generateMultimodalResponse(
        for messages: [ChatMessage], 
        temperature: Double? = nil, 
        maxTokens: Int? = nil,
        enableVisionAnalysis: Bool = true
    ) async throws -> String {
        // Check availability first
        let (available, reason) = isModelAvailable()
        guard available else {
            throw Abort(
                .serviceUnavailable, reason: reason ?? "Apple Intelligence model is not available")
        }

        guard !messages.isEmpty else {
            throw Abort(.badRequest, reason: "No messages provided")
        }

        // Validate language in all text messages before processing
        for message in messages {
            if !message.content.isEmpty {
                try validateLanguage(message.content)
            }
        }

        // Process multimodal content
        let processedMessages = try await processMultimodalMessages(messages, enableVisionAnalysis: enableVisionAnalysis)
        
        // Generate response using processed messages
        return try await generateResponse(
            for: processedMessages, 
            temperature: temperature, 
            maxTokens: maxTokens
        )
    }
    
    /// Process messages that may contain multimodal content
    func processMultimodalMessages(
        _ messages: [ChatMessage], 
        enableVisionAnalysis: Bool
    ) async throws -> [ChatMessage] {
        var processedMessages: [ChatMessage] = []
        
        for message in messages {
            if let multimodalContent = message.multimodalContent {
                // Process multimodal content
                let processedContent = try await processMultimodalContent(
                    multimodalContent, 
                    enableVisionAnalysis: enableVisionAnalysis
                )
                
                print("DEBUG: Processed multimodal content: \(processedContent.prefix(200))...")
                
                // Check language of processed content
                if let detectedLang = detectLanguage(from: processedContent) {
                    print("DEBUG: Processed content language: \(detectedLang)")
                }
                
                // Create new message with processed content
                let processedMessage = ChatMessage(
                    role: message.role,
                    content: processedContent,
                    name: message.name
                )
                processedMessages.append(processedMessage)
            } else {
                // Regular text message, no processing needed
                processedMessages.append(message)
            }
        }
        
        return processedMessages
    }
    
    /// Process individual multimodal content
    private func processMultimodalContent(
        _ content: [MessageContent], 
        enableVisionAnalysis: Bool
    ) async throws -> String {
        var processedParts: [String] = []
        
        for contentItem in content {
            print("DEBUG: Processing content type: \(contentItem.type)")
            
            switch contentItem.type {
            case "text":
                if let text = contentItem.text {
                    print("DEBUG: Processing text: \(text.prefix(50))...")
                    processedParts.append(text)
                }
                
            case "image_url":
                if let imageUrl = contentItem.imageUrl {
                    print("DEBUG: Processing image URL: \(imageUrl.url.prefix(100))...")
                    
                    // Check if it's a data URL (base64 encoded image)
                    if imageUrl.url.hasPrefix("data:image/") {
                        // Extract base64 data from data URL
                        if let commaIndex = imageUrl.url.firstIndex(of: ",") {
                            let base64String = String(imageUrl.url[imageUrl.url.index(after: commaIndex)...])
                            
                            // Create ImageData from the base64 string
                            let imageData = ImageData(data: base64String, format: "png", detail: nil)
                            let imageAnalysis = try await processImageData(imageData, enableVisionAnalysis: enableVisionAnalysis)
                            processedParts.append(imageAnalysis)
                        } else {
                            processedParts.append("[Image URL: \(imageUrl.url.prefix(50))...]")
                        }
                    } else {
                        // Regular URL (for future implementation)
                        processedParts.append("[Image URL: \(imageUrl.url)]")
                    }
                }
                
            case "image_data":
                if let imageData = contentItem.imageData {
                    print("DEBUG: Processing image data: format=\(imageData.format), size=\(imageData.data.count) chars")
                    // Process base64 image data
                    let imageAnalysis = try await processImageData(imageData, enableVisionAnalysis: enableVisionAnalysis)
                    processedParts.append(imageAnalysis)
                }
                
            default:
                print("DEBUG: Unknown content type: \(contentItem.type)")
                // Unknown content type, skip
                continue
            }
        }
        
        return processedParts.joined(separator: "\n\n")
    }
    
    /// Process base64 image data
    private func processImageData(
        _ imageData: ImageData, 
        enableVisionAnalysis: Bool
    ) async throws -> String {
        guard let data = Data(base64Encoded: imageData.data) else {
            throw Abort(.badRequest, reason: "Invalid base64 image data")
        }
        
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else {
            throw Abort(.badRequest, reason: "Invalid image format")
        }
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else {
            throw Abort(.badRequest, reason: "Invalid image format")
        }
        #else
        throw Abort(.badRequest, reason: "Image processing not supported on this platform")
        #endif
        
        if enableVisionAnalysis {
            // Use VisionServiceManager for comprehensive analysis
            let visionManager = VisionServiceManager.shared
            let analysis = try await visionManager.analyzeImage(image)
            
            // Create a more detailed and contextual description
            var description = "User uploaded an image with the following analysis:\n\n"
            
            if !analysis.textContent.isEmpty {
                description += "📝 Text content found: \"\(analysis.textContent)\"\n\n"
            }
            
            if !analysis.objectDetections.isEmpty {
                let objectLabels = analysis.objectDetections.map { "\($0.label) (\(Int($0.confidence * 100))%)" }
                description += "🔍 Objects detected: \(objectLabels.joined(separator: ", "))\n\n"
            }
            
            description += "📊 Overall analysis confidence: \(Int(analysis.confidence * 100))%\n\n"
            description += "Please analyze this image and respond to the user's question about it."
            
            return description
        } else {
            // Simple image reference
            return "[Image: \(imageData.format.uppercased()) format, \(data.count) bytes]"
        }
    }
    
    /// Convert multimodal messages to transcript entries
    func convertMultimodalMessagesToTranscript(_ messages: [ChatMessage]) -> [Transcript.Entry] {
        var entries: [Transcript.Entry] = []

        for message in messages {
            let textSegment = Transcript.TextSegment(content: message.content)

            switch message.role.lowercased() {
            case "system":
                let instructions = Transcript.Instructions(
                    segments: [.text(textSegment)],
                    toolDefinitions: []
                )
                entries.append(.instructions(instructions))

            case "user":
                let prompt = Transcript.Prompt(
                    segments: [.text(textSegment)]
                )
                entries.append(.prompt(prompt))

            case "assistant":
                let response = Transcript.Response(
                    assetIDs: [],
                    segments: [.text(textSegment)]
                )
                entries.append(.response(response))

            default:
                let prompt = Transcript.Prompt(
                    segments: [.text(textSegment)]
                )
                entries.append(.prompt(prompt))
            }
        }

        return entries
    }
}

// Global instance of the Apple Intelligence manager
let aiManager = OnDeviceModelManager()
