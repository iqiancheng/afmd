//
//  VaporServerManager.swift
//  afmd
//
//  Created by Channing Dai on 6/15/25.
//

import Combine
import Foundation
import FoundationModels
import Vapor
import NIOFoundationCompat

@MainActor
class VaporServerManager: ObservableObject {
    @Published var isRunning = false
    @Published var lastError: String?

    private var app: Application?
    private var serverTask: Task<Void, Never>?
    private weak var viewModel: ServerViewModel?

    private static let modelName = "AFM-on-device"
    private static var loggingBootstrapped = false
    
    func setViewModel(_ viewModel: ServerViewModel) {
        self.viewModel = viewModel
    }

    func startServer(configuration: ServerConfiguration) async {
        guard !isRunning else { return }

        do {
            // Create Vapor application
            var env = try Environment.detect()

            // Only bootstrap logging system once per process
            // This prevents the "logging system can only be initialized once per process" error
            // when stopping and restarting the server
            if !Self.loggingBootstrapped {
                try LoggingSystem.bootstrap(from: &env)
                Self.loggingBootstrapped = true
            }

            let app = Application(env)
            self.app = app

            // Fix for running Vapor in iOS/macOS app - clear command line arguments
            app.environment.arguments = [app.environment.arguments[0]]

            // Configure request body size limit for image uploads
            app.routes.defaultMaxBodySize = "50mb"
            
            // Configure routes
            configureRoutes(app)

            // Configure server
            app.http.server.configuration.hostname = configuration.host
            app.http.server.configuration.port = configuration.port

            // Start server in background task
            serverTask = Task {
                do {
                    try await app.execute()
                } catch {
                    await MainActor.run {
                        self.lastError = error.localizedDescription
                        self.isRunning = false
                    }
                }
            }

            isRunning = true
            lastError = nil

        } catch {
            lastError = error.localizedDescription
        }
    }

    func stopServer() async {
        guard isRunning else { return }
        

        // Cancel the server task
        serverTask?.cancel()
        serverTask = nil

        // Shutdown the application
        if let app = app {
            try? await app.asyncShutdown()
            self.app = nil
        }

        isRunning = false
    }

    private func configureRoutes(_ app: Application) {
        // Define octet stream media type for image uploads
        let octetStream = HTTPMediaType(type: "application", subType: "octet-stream")
        
        // Health check endpoint
        app.get("health") { req async -> HTTPStatus in
            let status = HTTPStatus.ok
            return status
        }

        // Model status endpoint
        app.get("status") { req async throws -> ServerStatus in
            let (available, reason) = await aiManager.isModelAvailable()
            let supportedLanguages = await aiManager.getSupportedLanguages()

            let status = ServerStatus(
                modelAvailable: available,
                reason: reason ?? "Model is available",
                supportedLanguages: supportedLanguages,
                serverVersion: "1.0.0",
                appleIntelligenceCompatible: true
            )
            
            self.viewModel?.addLog(level: .debug, category: .response, message: "Status response sent", details: "Model available: \(available), Status: 200")
            return status
        }

        // OpenAI compatible endpoints
        let v1 = app.grouped("v1")

        // List models endpoint
        v1.get("models") { req async throws -> ModelsResponse in
            let (available, _) = await aiManager.isModelAvailable()

            var models: [ModelInfo] = []

            if available {
                models.append(
                    ModelInfo(
                        id: Self.modelName,
                        object: "model",
                        created: Int(Date().timeIntervalSince1970),
                        ownedBy: "AFM-on-device-openai"
                    ))
            }

            let response = ModelsResponse(
                object: "list",
                data: models
            )
            
            self.viewModel?.addLog(level: .debug, category: .response, message: "", details: "Models count: \(models.count), Status: 200")
            return response
        }

        // Chat completions endpoint (main endpoint) - now supports multimodal
        v1.post("chat", "completions") { req async throws -> Response in
            let chatRequest = try req.content.decode(ChatCompletionRequest.self)
            
            // Log request details
            let messageCount = chatRequest.messages.count
            let isStreaming = chatRequest.stream == true
            let model = chatRequest.model ?? Self.modelName
            
            // Check if request contains multimodal content
            let hasMultimodalContent = chatRequest.messages.contains { message in
                message.multimodalContent != nil
            }
            
            // Log request content
            let requestContent = chatRequest.messages.map { msg in
                let hasImages = msg.multimodalContent?.contains { $0.type == "image_data" || $0.type == "image_url" } == true
                return "\(msg.role): \(msg.content)\(hasImages ? " [with images]" : "")"
            }.joined(separator: " | ")
            
            self.viewModel?.addLog(level: .debug, category: .request, message: "", details: "Messages: \(messageCount), Streaming: \(isStreaming), Model: \(model), Multimodal: \(hasMultimodalContent)")
            self.viewModel?.addLog(level: .info, category: .request, message: "", details: requestContent)

            // Validate request
            guard !chatRequest.messages.isEmpty else {
                self.viewModel?.addLog(level: .error, category: .request, message: "", details: "No messages provided")
                throw Abort(.badRequest, reason: "No messages provided")
            }

            do {
                // Handle streaming vs non-streaming
                if chatRequest.stream == true {
                    return try await self.handleStreamingResponse(chatRequest)
                }

                // Generate response using the manager
                let response: String
                if hasMultimodalContent {
                    response = try await aiManager.generateMultimodalResponse(
                        for: chatRequest.messages,
                        temperature: chatRequest.temperature,
                        maxTokens: chatRequest.maxTokens,
                        enableVisionAnalysis: true
                    )
                } else {
                    response = try await aiManager.generateResponse(
                        for: chatRequest.messages,
                        temperature: chatRequest.temperature,
                        maxTokens: chatRequest.maxTokens
                    )
                }

                let chatResponse = ChatCompletionResponse(
                    id: "afmd-\(UUID().uuidString)",
                    object: "chat.completion",
                    created: Int(Date().timeIntervalSince1970),
                    model: chatRequest.model ?? Self.modelName,
                    choices: [
                        ChatCompletionChoice(
                            index: 0,
                            message: ChatMessage(
                                role: "assistant",
                                content: response
                            ),
                            finishReason: "stop"
                        )
                    ]
                )

                // Encode response as JSON
                let jsonData = try JSONEncoder().encode(chatResponse)
                var res = Response()
                res.headers.contentType = .json
                res.body = .init(data: jsonData)
                
                self.viewModel?.addLog(level: .info, category: .response, message: "", details: response + "\n\nlength: \(response.count) characters, Status: 200")
                return res
            } catch let error as AbortError {
                self.viewModel?.addLog(level: .error, category: .response, message: "", details: "AbortError: \(error.reason), Status: \(error.status.code)")
                throw error
            } catch {
                // Handle specific FoundationModels errors
                if let foundationError = error as? FoundationModels.LanguageModelSession.GenerationError {
                    switch foundationError {
                    case .unsupportedLanguageOrLocale(let context):
                        let supportedLanguages = await aiManager.getSupportedLanguages()
                        let supportedCodes = await aiManager.getSupportedLanguageCodes()
                        let errorMessage = "Unsupported language detected. Supported languages: \(supportedLanguages.joined(separator: ", ")) (codes: \(supportedCodes.joined(separator: ", "))). Please use English or another supported language."
                        self.viewModel?.addLog(level: .error, category: .response, message: "", details: "Language Error: \(errorMessage), Status: 400")
                        throw Abort(.badRequest, reason: errorMessage)
                    default:
                        self.viewModel?.addLog(level: .error, category: .response, message: "", details: "FoundationModels Error: \(foundationError.localizedDescription), Status: 500")
                        throw Abort(.internalServerError, reason: "Language model error: \(foundationError.localizedDescription)")
                    }
                }
                
                self.viewModel?.addLog(level: .error, category: .response, message: "", details: "Error: \(error.localizedDescription), Status: 500")
                throw Abort(
                    .internalServerError,
                    reason: "Error generating response: \(error.localizedDescription)")
            }
        }
        
        // MARK: - Multimodal Chat Completions Endpoint
        
        // Multimodal chat completions endpoint (supports text + images)
        v1.post("chat", "completions", "multimodal") { req async throws -> Response in
            let chatRequest = try req.content.decode(MultimodalChatRequest.self)
            
            // Log request details
            let messageCount = chatRequest.messages.count
            let isStreaming = chatRequest.stream == true
            let model = chatRequest.model ?? Self.modelName
            let visionAnalysis = chatRequest.visionAnalysis ?? true
            
            // Log request content
            let requestContent = chatRequest.messages.map { msg in
                let hasImages = msg.multimodalContent?.contains { $0.type == "image_data" || $0.type == "image_url" } == true
                return "\(msg.role): \(msg.content)\(hasImages ? " [with images]" : "")"
            }.joined(separator: " | ")
            
            self.viewModel?.addLog(level: .debug, category: .request, message: "Multimodal request", details: "Messages: \(messageCount), Streaming: \(isStreaming), Model: \(model), Vision: \(visionAnalysis)")
            self.viewModel?.addLog(level: .info, category: .request, message: "", details: requestContent)

            // Validate request
            guard !chatRequest.messages.isEmpty else {
                self.viewModel?.addLog(level: .error, category: .request, message: "", details: "No messages provided")
                throw Abort(.badRequest, reason: "No messages provided")
            }

            do {
                // Handle streaming vs non-streaming
                if chatRequest.stream == true {
                    return try await self.handleMultimodalStreamingResponse(chatRequest)
                }

                // Generate multimodal response using the manager
                let response = try await aiManager.generateMultimodalResponse(
                    for: chatRequest.messages,
                    temperature: chatRequest.temperature,
                    maxTokens: chatRequest.maxTokens,
                    enableVisionAnalysis: visionAnalysis
                )

                let chatResponse = ChatCompletionResponse(
                    id: "afmd-multimodal-\(UUID().uuidString)",
                    object: "chat.completion",
                    created: Int(Date().timeIntervalSince1970),
                    model: chatRequest.model ?? Self.modelName,
                    choices: [
                        ChatCompletionChoice(
                            index: 0,
                            message: ChatMessage(
                                role: "assistant",
                                content: response
                            ),
                            finishReason: "stop"
                        )
                    ]
                )

                // Encode response as JSON
                let jsonData = try JSONEncoder().encode(chatResponse)
                var res = Response()
                res.headers.contentType = .json
                res.body = .init(data: jsonData)
                
                self.viewModel?.addLog(level: .info, category: .response, message: "Multimodal response", details: response + "\n\nlength: \(response.count) characters, Status: 200")
                return res
            } catch let error as AbortError {
                self.viewModel?.addLog(level: .error, category: .response, message: "Multimodal error", details: "AbortError: \(error.reason), Status: \(error.status.code)")
                throw error
            } catch {
                // Handle specific FoundationModels errors
                if let foundationError = error as? FoundationModels.LanguageModelSession.GenerationError {
                    switch foundationError {
                    case .unsupportedLanguageOrLocale(let context):
                        let supportedLanguages = await aiManager.getSupportedLanguages()
                        let supportedCodes = await aiManager.getSupportedLanguageCodes()
                        let errorMessage = "Unsupported language detected. Supported languages: \(supportedLanguages.joined(separator: ", ")) (codes: \(supportedCodes.joined(separator: ", "))). Please use English or another supported language."
                        self.viewModel?.addLog(level: .error, category: .response, message: "Multimodal language error", details: "Language Error: \(errorMessage), Status: 400")
                        throw Abort(.badRequest, reason: errorMessage)
                    default:
                        self.viewModel?.addLog(level: .error, category: .response, message: "Multimodal FoundationModels error", details: "FoundationModels Error: \(foundationError.localizedDescription), Status: 500")
                        throw Abort(.internalServerError, reason: "Language model error: \(foundationError.localizedDescription)")
                    }
                }
                
                self.viewModel?.addLog(level: .error, category: .response, message: "Multimodal error", details: "Error: \(error.localizedDescription), Status: 500")
                throw Abort(
                    .internalServerError,
                    reason: "Error generating multimodal response: \(error.localizedDescription)")
            }
        }
        
        // MARK: - Vision Analysis Endpoints
        
        // OCR endpoint
        v1.post("vision", "ocr") { req async throws -> Response in
            guard req.headers.contentType == octetStream else {
                throw Abort(.unsupportedMediaType, reason: "Content-Type must be application/octet-stream")
            }
            let imageData = Data(buffer: req.body.data ?? ByteBuffer())
            
            self.viewModel?.addLog(level: .debug, category: .request, message: "OCR request", details: "Image size: \(imageData.count) bytes")
            
            do {
                let visionManager = VisionServiceManager.shared
                let ocrResult = try await visionManager.extractText(from: imageData)
                
                let response = [
                    "text": ocrResult.text,
                    "confidence": ocrResult.confidence,
                    "language": ocrResult.language ?? "unknown"
                ]
                
                let jsonData = try JSONSerialization.data(withJSONObject: response)
                var res = Response()
                res.headers.contentType = .json
                res.body = .init(data: jsonData)
                
                self.viewModel?.addLog(level: .info, category: .response, message: "OCR success", details: "Text length: \(ocrResult.text.count), Confidence: \(Int(ocrResult.confidence * 100))%")
                return res
            } catch {
                self.viewModel?.addLog(level: .error, category: .response, message: "OCR error", details: "Error: \(error.localizedDescription)")
                throw Abort(.internalServerError, reason: "OCR processing failed: \(error.localizedDescription)")
            }
        }
        
        // Object detection endpoint
        v1.post("vision", "detect") { req async throws -> Response in
            guard req.headers.contentType == octetStream else {
                throw Abort(.unsupportedMediaType, reason: "Content-Type must be application/octet-stream")
            }
            let imageData = Data(buffer: req.body.data ?? ByteBuffer())
            
            self.viewModel?.addLog(level: .debug, category: .request, message: "Object detection request", details: "Image size: \(imageData.count) bytes")
            
            do {
                let visionManager = VisionServiceManager.shared
                let objects = try await visionManager.detectObjects(in: imageData)
                
                let response = [
                    "objects": objects.map { obj in
                        [
                            "label": obj.label,
                            "confidence": obj.confidence,
                            "description": obj.description
                        ]
                    }
                ]
                
                let jsonData = try JSONSerialization.data(withJSONObject: response)
                var res = Response()
                res.headers.contentType = .json
                res.body = .init(data: jsonData)
                
                self.viewModel?.addLog(level: .info, category: .response, message: "Object detection success", details: "Objects found: \(objects.count)")
                return res
            } catch {
                self.viewModel?.addLog(level: .error, category: .response, message: "Object detection error", details: "Error: \(error.localizedDescription)")
                throw Abort(.internalServerError, reason: "Object detection failed: \(error.localizedDescription)")
            }
        }
        
        // Comprehensive image analysis endpoint
        v1.post("vision", "analyze") { req async throws -> Response in
            guard req.headers.contentType == octetStream else {
                throw Abort(.unsupportedMediaType, reason: "Content-Type must be application/octet-stream")
            }
            let imageData = Data(buffer: req.body.data ?? ByteBuffer())
            
            self.viewModel?.addLog(level: .debug, category: .request, message: "Image analysis request", details: "Image size: \(imageData.count) bytes")
            
            do {
                let visionManager = VisionServiceManager.shared
                let analysis = try await visionManager.analyzeImage(imageData)
                
                let detectedObjects = analysis.objectDetections.map { obj in
                    DetectedObjectInfo(
                        label: obj.label,
                        confidence: obj.confidence,
                        boundingBox: BoundingBox(
                            x: Double(obj.boundingBox.origin.x),
                            y: Double(obj.boundingBox.origin.y),
                            width: Double(obj.boundingBox.size.width),
                            height: Double(obj.boundingBox.size.height)
                        ),
                        description: obj.description
                    )
                }
                
                let visionResult = VisionAnalysisResult(
                    textContent: analysis.textContent,
                    objectDetections: detectedObjects,
                    imageDescription: analysis.imageDescription,
                    confidence: analysis.confidence,
                    language: visionManager.detectLanguageInText(analysis.textContent)
                )
                
                let response = VisionAnalysisResponse(
                    id: "vision-\(UUID().uuidString)",
                    object: "vision.analysis",
                    created: Int(Date().timeIntervalSince1970),
                    model: Self.modelName,
                    analysis: visionResult,
                    processingTime: analysis.processingTime
                )
                
                let jsonData = try JSONEncoder().encode(response)
                var res = Response()
                res.headers.contentType = .json
                res.body = .init(data: jsonData)
                
                self.viewModel?.addLog(level: .info, category: .response, message: "Image analysis success", details: "Text: \(analysis.textContent.count) chars, Objects: \(detectedObjects.count), Confidence: \(Int(analysis.confidence * 100))%")
                return res
            } catch {
                self.viewModel?.addLog(level: .error, category: .response, message: "Image analysis error", details: "Error: \(error.localizedDescription)")
                throw Abort(.internalServerError, reason: "Image analysis failed: \(error.localizedDescription)")
            }
        }
    }

    // Helper function to handle streaming responses
    private func handleStreamingResponse(_ chatRequest: ChatCompletionRequest) async throws
        -> Response
    {
        // Check if request contains multimodal content
        let hasMultimodalContent = chatRequest.messages.contains { message in
            message.multimodalContent != nil
        }
        
        let response = Response()
        response.headers.replaceOrAdd(name: .contentType, value: "text/event-stream")
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-cache")
        response.headers.replaceOrAdd(name: .connection, value: "keep-alive")
        response.headers.replaceOrAdd(name: "Access-Control-Allow-Origin", value: "*")
        response.headers.replaceOrAdd(name: "Access-Control-Allow-Headers", value: "Cache-Control")

        // Create the streaming body using Vapor's Response.Body(stream:)
        response.body = Response.Body(stream: { writer in
            Task {
                do {
                    // This is already logged in the main endpoint, so we don't need to log it again here
                    // Check availability first
                    let (available, reason) = await aiManager.isModelAvailable()
                    guard available else {
                        self.viewModel?.addLog(level: .error, category: .model, message: "Model not available", details: reason)
                        let errorData = """
                            data: {"error": {"message": "\(reason ?? "Model not available")", "type": "unavailable_error"}}

                            data: [DONE]

                            """
                        try await writer.write(.buffer(ByteBuffer(string: errorData)))
                        writer.write(.end)
                        return
                    }

                    // Process messages based on whether they contain multimodal content
                    let processedMessages: [ChatMessage]
                    if hasMultimodalContent {
                        print("DEBUG: Processing multimodal messages...")
                        processedMessages = try await aiManager.processMultimodalMessages(
                            chatRequest.messages, 
                            enableVisionAnalysis: true
                        )
                    } else {
                        print("DEBUG: Using regular messages")
                        processedMessages = chatRequest.messages
                    }

                    // Get the last message as the current prompt
                    let lastMessage = processedMessages.last!
                    let currentPrompt = lastMessage.content
                    
                    print("DEBUG: Current prompt: \(currentPrompt.prefix(100))...")
                    if let promptLang = await aiManager.detectLanguage(from: currentPrompt) {
                        print("DEBUG: Current prompt language: \(promptLang)")
                    }

                    // Validate language before processing
                    try await aiManager.validateLanguage(currentPrompt)

                    // Convert previous messages (excluding the last one) to transcript
                    let previousMessages =
                        processedMessages.count > 1 ? Array(processedMessages.dropLast()) : []
                    print("DEBUG: Previous messages count: \(previousMessages.count)")
                    let transcriptEntries = await aiManager.convertMessagesToTranscript(
                        previousMessages)

                    // Create transcript with conversation history
                    let transcript = Transcript(entries: transcriptEntries)

                    // Create new session with the conversation transcript
                    let session = LanguageModelSession(
                        model: SystemLanguageModel.default,
                        transcript: transcript
                    )

                    // Create generation options
                    var options = GenerationOptions()
                    if let temp = chatRequest.temperature {
                        options = GenerationOptions(
                            temperature: temp, maximumResponseTokens: chatRequest.maxTokens)
                    } else if let maxTokens = chatRequest.maxTokens {
                        options = GenerationOptions(maximumResponseTokens: maxTokens)
                    }

                    // Get the streaming response from the session
                    print("DEBUG: Getting streaming response")
                    self.viewModel?.addLog(level: .debug, category: .response, message: "Getting streaming response from model")
                    let responseStream = session.streamResponse(to: currentPrompt, options: options)

                    // Response metadata
                    let responseId = "afm-\(UUID().uuidString)"
                    let created = Int(Date().timeIntervalSince1970)

                    // Track previous content to calculate deltas
                    var previousContent = ""
                    var isFirstChunk = true

                    // Iterate through the stream and yield partial responses
                    print("DEBUG: Starting stream iteration")
                    for try await cumulativeResponse in responseStream {
                        print("DEBUG: Processing stream chunk")
                        // Calculate the delta (new content since last iteration)
                        let deltaContent = String(cumulativeResponse.content.dropFirst(previousContent.count))

                        // Skip empty deltas (except for the first chunk which might include role)
                        if deltaContent.isEmpty && !isFirstChunk {
                            continue
                        }

                        let streamResponse = ChatCompletionStreamResponse(
                            id: responseId,
                            object: "chat.completion.chunk",
                            created: created,
                            model: Self.modelName,
                            choices: [
                                ChatCompletionStreamChoice(
                                    index: 0,
                                    delta: ChatCompletionDelta(
                                        role: isFirstChunk ? "assistant" : nil,
                                        content: deltaContent.isEmpty ? nil : deltaContent
                                    ),
                                    finishReason: nil
                                )
                            ]
                        )

                        let encoder = JSONEncoder()
                        let jsonData = try encoder.encode(streamResponse)
                        let sseData = "data: \(String(data: jsonData, encoding: .utf8)!)\n\n"

                        print("DEBUG: Writing SSE data chunk: \(sseData)")
                        try await writer.write(.buffer(ByteBuffer(string: sseData)))
                        print("DEBUG: Successfully wrote SSE data chunk")

                        // Update tracking variables
                        previousContent = cumulativeResponse.content
                        isFirstChunk = false
                    }

                    // Send final completion message
                    let finalResponse = ChatCompletionStreamResponse(
                        id: responseId,
                        object: "chat.completion.chunk",
                        created: created,
                        model: Self.modelName,
                        choices: [
                            ChatCompletionStreamChoice(
                                index: 0,
                                delta: ChatCompletionDelta(
                                    role: nil,
                                    content: nil
                                ),
                                finishReason: "stop"
                            )
                        ]
                    )

                    let encoder = JSONEncoder()
                    let finalJsonData = try encoder.encode(finalResponse)
                    let finalSseData = "data: \(String(data: finalJsonData, encoding: .utf8)!)\n\n"

                    try await writer.write(.buffer(ByteBuffer(string: finalSseData)))

                    // Send [DONE] to indicate stream completion
                    try await writer.write(.buffer(ByteBuffer(string: "data: [DONE]\n\n")))

                    // Complete the stream
                    writer.write(.end)
                    
                    // Log streaming completion
                    self.viewModel?.addLog(level: .info, category: .response, message: "", details: "Total content length: \(previousContent.count) characters, Status: 200")
                    self.viewModel?.addLog(level: .info, category: .response, message: "", details: previousContent)

                } catch {
                    // Print full error and stack trace to server output
                    print("Error in chat completion stream: \(error)")
                    print("Error details:")
                    dump(error)
                    
                    // Handle specific language errors
                    var errorMessage = error.localizedDescription
                    var errorType = "internal_error"
                    var statusCode = 500
                    
                    if let abortError = error as? AbortError {
                        statusCode = Int(abortError.status.code)
                        errorMessage = abortError.reason
                        
                        if abortError.status.code == 400 && errorMessage.contains("Unsupported language") {
                            errorType = "unsupported_language"
                        }
                    }
                    
                    // Log streaming error
                    self.viewModel?.addLog(level: .error, category: .response, message: "", details: "Error: \(errorMessage), Status: \(statusCode)")

                    // Handle errors by sending error message in SSE format
                    let errorData = """
                        data: {"error": {"message": "\(errorMessage)", "type": "\(errorType)"}}

                        data: [DONE]

                        """
                    try? await writer.write(.buffer(ByteBuffer(string: errorData)))
                    writer.write(.end)
                }
            }
        })

        return response
    }
    
    // Helper function to handle multimodal streaming responses
    private func handleMultimodalStreamingResponse(_ chatRequest: MultimodalChatRequest) async throws -> Response {
        let response = Response()
        response.headers.replaceOrAdd(name: .contentType, value: "text/event-stream")
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-cache")
        response.headers.replaceOrAdd(name: .connection, value: "keep-alive")
        response.headers.replaceOrAdd(name: "Access-Control-Allow-Origin", value: "*")
        response.headers.replaceOrAdd(name: "Access-Control-Allow-Headers", value: "Cache-Control")

        // Create the streaming body using Vapor's Response.Body(stream:)
        response.body = Response.Body(stream: { writer in
            Task {
                do {
                    // Check availability first
                    let (available, reason) = await aiManager.isModelAvailable()
                    guard available else {
                        self.viewModel?.addLog(level: .error, category: .model, message: "Model not available", details: reason)
                        let errorData = """
                            data: {"error": {"message": "\(reason ?? "Model not available")", "type": "unavailable_error"}}

                            data: [DONE]

                            """
                        try await writer.write(.buffer(ByteBuffer(string: errorData)))
                        writer.write(.end)
                        return
                    }

                    // Process multimodal content first
                    let processedMessages = try await aiManager.processMultimodalMessages(
                        chatRequest.messages, 
                        enableVisionAnalysis: true
                    )

                    // Get the last message as the current prompt
                    let lastMessage = processedMessages.last!
                    let currentPrompt = lastMessage.content

                    // Validate language before processing
                    try await aiManager.validateLanguage(currentPrompt)

                    // Convert previous messages (excluding the last one) to transcript
                    let previousMessages = processedMessages.count > 1 ? Array(processedMessages.dropLast()) : []
                    let transcriptEntries = await aiManager.convertMessagesToTranscript(previousMessages)

                    // Create transcript with conversation history
                    let transcript = Transcript(entries: transcriptEntries)

                    // Create new session with the conversation transcript
                    let session = LanguageModelSession(
                        model: SystemLanguageModel.default,
                        transcript: transcript
                    )

                    // Create generation options
                    var options = GenerationOptions()
                    if let temp = chatRequest.temperature {
                        options = GenerationOptions(
                            temperature: temp, 
                            maximumResponseTokens: chatRequest.maxTokens
                        )
                    } else if let maxTokens = chatRequest.maxTokens {
                        options = GenerationOptions(maximumResponseTokens: maxTokens)
                    }

                    // Get the streaming response from the session
                    self.viewModel?.addLog(level: .debug, category: .response, message: "Getting multimodal streaming response from model")
                    let responseStream = session.streamResponse(to: currentPrompt, options: options)

                    // Response metadata
                    let responseId = "afmd-multimodal-\(UUID().uuidString)"
                    let created = Int(Date().timeIntervalSince1970)

                    // Track previous content to calculate deltas
                    var previousContent = ""
                    var isFirstChunk = true

                    // Iterate through the stream and yield partial responses
                    for try await cumulativeResponse in responseStream {
                        // Calculate the delta (new content since last iteration)
                        let deltaContent = String(cumulativeResponse.content.dropFirst(previousContent.count))

                        // Skip empty deltas (except for the first chunk which might include role)
                        if deltaContent.isEmpty && !isFirstChunk {
                            continue
                        }

                        let streamResponse = ChatCompletionStreamResponse(
                            id: responseId,
                            object: "chat.completion.chunk",
                            created: created,
                            model: Self.modelName,
                            choices: [
                                ChatCompletionStreamChoice(
                                    index: 0,
                                    delta: ChatCompletionDelta(
                                        role: isFirstChunk ? "assistant" : nil,
                                        content: deltaContent.isEmpty ? nil : deltaContent
                                    ),
                                    finishReason: nil
                                )
                            ]
                        )

                        let encoder = JSONEncoder()
                        let jsonData = try encoder.encode(streamResponse)
                        let sseData = "data: \(String(data: jsonData, encoding: .utf8)!)\n\n"

                        try await writer.write(.buffer(ByteBuffer(string: sseData)))

                        // Update tracking variables
                        previousContent = cumulativeResponse.content
                        isFirstChunk = false
                    }

                    // Send final completion message
                    let finalResponse = ChatCompletionStreamResponse(
                        id: responseId,
                        object: "chat.completion.chunk",
                        created: created,
                        model: Self.modelName,
                        choices: [
                            ChatCompletionStreamChoice(
                                index: 0,
                                delta: ChatCompletionDelta(
                                    role: nil,
                                    content: nil
                                ),
                                finishReason: "stop"
                            )
                        ]
                    )

                    let encoder = JSONEncoder()
                    let finalJsonData = try encoder.encode(finalResponse)
                    let finalSseData = "data: \(String(data: finalJsonData, encoding: .utf8)!)\n\n"

                    try await writer.write(.buffer(ByteBuffer(string: finalSseData)))

                    // Send [DONE] to indicate stream completion
                    try await writer.write(.buffer(ByteBuffer(string: "data: [DONE]\n\n")))

                    // Complete the stream
                    writer.write(.end)
                    
                    // Log streaming completion
                    self.viewModel?.addLog(level: .info, category: .response, message: "Multimodal streaming completed", details: "Total content length: \(previousContent.count) characters, Status: 200")

                } catch {
                    // Print full error and stack trace to server output
                    print("Error in multimodal chat completion stream: \(error)")
                    print("Error details:")
                    dump(error)
                    
                    // Handle specific language errors
                    var errorMessage = error.localizedDescription
                    var errorType = "internal_error"
                    var statusCode = 500
                    
                    if let abortError = error as? AbortError {
                        statusCode = Int(abortError.status.code)
                        errorMessage = abortError.reason
                        
                        if abortError.status.code == 400 && errorMessage.contains("Unsupported language") {
                            errorType = "unsupported_language"
                        }
                    }
                    
                    // Log streaming error
                    self.viewModel?.addLog(level: .error, category: .response, message: "Multimodal streaming error", details: "Error: \(errorMessage), Status: \(statusCode)")

                    // Handle errors by sending error message in SSE format
                    let errorData = """
                        data: {"error": {"message": "\(errorMessage)", "type": "\(errorType)"}}

                        data: [DONE]

                        """
                    try? await writer.write(.buffer(ByteBuffer(string: errorData)))
                    writer.write(.end)
                }
            }
        })

        return response
    }

    deinit {
        Task { [app] in
            try? await app?.asyncShutdown()
        }
    }
}
