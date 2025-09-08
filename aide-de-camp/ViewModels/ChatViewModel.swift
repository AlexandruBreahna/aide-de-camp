//
//  ChatViewModel.swift
//  aide-de-camp
//
//  Created by Alexander Eckhart on 30.08.25.
//

import Foundation
import Combine

final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var alertMessage: String? = nil
    @Published var errorMessage: String? = nil
    @Published var isRetrying: Bool = false
    private var retryWorkItem: DispatchWorkItem?

    private var cancellables = Set<AnyCancellable>()
    private let openAIService = OpenAIService()
    private let webhookService = WebhookService()
    private var loggedEvents: Set<String> = []

    init() {
        loadConversation()
    }
    
    private func saveConversation() {
        guard let url = getConversationFileURL() else { return }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        if let data = try? encoder.encode(messages) {
            try? data.write(to: url)
        }
    }

    private func loadConversation() {
        guard let url = getConversationFileURL(),
              let data = try? Data(contentsOf: url) else { return }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        if let loadedMessages = try? decoder.decode([Message].self, from: data) {
            // Filter out any thinking messages that shouldn't have been saved
            messages = loadedMessages.filter { $0.text != Constants.SystemMessages.aiThinking }
        }
    }

    private func getConversationFileURL() -> URL? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return documentsPath?.appendingPathComponent("conversation.json")
    }
    
    func retryLastMessage() {
        guard let lastUserMessage = messages.last(where: { $0.isFromUser }) else { return }
        
        // Remove error message
        if let errorIndex = messages.lastIndex(where: { !$0.isFromUser && $0.text.starts(with: "Error:") }) {
            messages.remove(at: errorIndex)
        }
        
        // Retry sending
        errorMessage = nil
        sendMessageInternal(text: lastUserMessage.text)
    }

    // Update appendMessage to save after each message
    private func appendMessage(_ message: Message) {
        messages.append(message)

        if messages.count > Constants.maxMessageCount {
            messages.removeFirst(messages.count - Constants.maxMessageCount)
        }
        
        // Only save if it's not a thinking message
        if message.text != Constants.SystemMessages.aiThinking {
            saveConversation()
        }
    }

    // Update startNewSession to delete saved file
    func startNewSession() {
        messages.removeAll()
        loggedEvents.removeAll()
        if let url = getConversationFileURL() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let openAIKey = KeychainStore.get(Constants.UserDefaultsKeys.openAIKey)
        guard !openAIKey.isEmpty else {
            alertMessage = Constants.SystemMessages.missingAPIKey
            return
        }
        
        guard let webhookURL = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.webhookURL),
              !webhookURL.isEmpty else {
            alertMessage = Constants.SystemMessages.missingWebhookURL
            return
        }
        
        // Store text and clear input
        let messageText = trimmed
        inputText = ""
        
        // Add user message
        let userMessage = Message(sender: .user, text: messageText)
        appendMessage(userMessage)
        
        sendMessageInternal(text: messageText)
    }
    
    private func sendMessageInternal(text: String) {
        isLoading = true
        errorMessage = nil
        
        let streamingMessage = Message(sender: .ai, text: Constants.SystemMessages.aiThinking)
        appendMessage(streamingMessage)
        let streamingId = streamingMessage.id
        
        HapticsService.shared.streamBegan()
        
        let openAIKey = KeychainStore.get(Constants.UserDefaultsKeys.openAIKey)
        let webhookURL = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.webhookURL) ?? ""
        
        guard !openAIKey.isEmpty && !webhookURL.isEmpty else {
            return
        }
        
        // Filter out thinking messages before sending
        let cleanMessages = messages.filter {
            $0.text != Constants.SystemMessages.aiThinking
        }
        
        // Use the retry-enabled method
        openAIService.sendMessageStreamWithRetry(
            messages: cleanMessages,
            apiKey: openAIKey,
            webhookURL: webhookURL,
            functionResponses: [],
            maxRetries: 2,
            onPartial: { [weak self] partial in
                DispatchQueue.main.async {
                    self?.isRetrying = false
                    if let idx = self?.messages.firstIndex(where: { $0.id == streamingId }) {
                        self?.messages[idx] = Message(id: streamingId, sender: .ai, text: partial)
                        // Save the updated message
                        if !partial.isEmpty && partial != Constants.SystemMessages.aiThinking {
                            self?.saveConversation()
                        }
                    }
                    HapticsService.shared.streamTick()
                }
            },
            onFunctionCall: { [weak self] functionCall in
                // Your existing function call handling code here
                self?.handleFunctionCall(functionCall, streamingId: streamingId, webhookURL: webhookURL, openAIKey: openAIKey)
            },
            onComplete: { [weak self] result in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.isRetrying = false
                    
                    switch result {
                    case .failure(let error):
                        if let idx = self?.messages.firstIndex(where: { $0.id == streamingId }) {
                            let errorText = self?.formatError(error) ?? "An error occurred"
                            self?.messages[idx] = Message(id: streamingId, sender: .ai, text: errorText)
                            self?.errorMessage = errorText
                        }
                        HapticsService.shared.streamEndedError()
                        
                    case .success:
                        self?.errorMessage = nil
                        self?.saveConversation()
                        HapticsService.shared.streamEndedSuccess()
                    }
                }
            }
        )
    }
    
    private func formatError(_ error: Error) -> String {
        let nsError = error as NSError
        
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return "No internet connection. Please check your network and try again."
            case NSURLErrorTimedOut:
                return "Request timed out. Please try again."
            default:
                return "Network error. Please check your connection and try again."
            }
        }
        
        if nsError.domain == "OpenAI API Error" {
            switch nsError.code {
            case 429:
                return "Rate limit exceeded. Please wait a moment and try again."
            case 401:
                return "Invalid API key. Please check your settings."
            case 500...599:
                return "OpenAI service is temporarily unavailable. Please try again later."
            default:
                return "OpenAI API error: \(nsError.localizedDescription)"
            }
        }
        
        return "Error: \(error.localizedDescription)"
    }

    private func handleFunctionCall(_ functionCall: FunctionCall, streamingId: UUID, webhookURL: String, openAIKey: String) {
        // IMPROVEMENT 1: Common JSON parsing
        let rawArgs = functionCall.function.arguments
        let argsData = rawArgs.data(using: .utf8) ?? Data()
        var json = (try? JSONSerialization.jsonObject(with: argsData)) as? [String: Any] ?? [:]
        
        // IMPROVEMENT 2: Early routing based on function name
        switch functionCall.function.name {
        case "retrieveEvents":
            handleRetrieveEvents(
                filters: json,
                functionCall: functionCall,
                streamingId: streamingId,
                webhookURL: webhookURL,
                openAIKey: openAIKey
            )
            
        case "logEvent":
            handleLogEvent(
                json: &json,
                functionCall: functionCall,
                streamingId: streamingId,
                webhookURL: webhookURL,
                openAIKey: openAIKey,
                rawArgs: rawArgs
            )
            
        default:
            // IMPROVEMENT 3: Handle unknown function calls
            DispatchQueue.main.async { [weak self] in
                self?.isLoading = false
                if let idx = self?.messages.firstIndex(where: { $0.id == streamingId }) {
                    self?.messages[idx] = Message(
                        id: streamingId,
                        sender: .ai,
                        text: "Unknown function: \(functionCall.function.name)"
                    )
                }
            }
        }
    }
    
    private func handleRetrieveEvents(
        filters: [String: Any],
        functionCall: FunctionCall,
        streamingId: UUID,
        webhookURL: String,
        openAIKey: String
    ) {
        WebhookService.shared.executeRequest(
            method: .get,
            operation: "retrieve",
            filters: filters,
            data: nil,
            webhookURL: webhookURL
        ) { [weak self] result in
            switch result {
            case .success(let response):
                self?.trackFunctionCall("retrieveEvents", success: true)
                self?.handleRetrievalResponse(
                    response,
                    streamingId: streamingId,
                    openAIKey: openAIKey,
                    webhookURL: webhookURL,
                    functionCall: functionCall
                )
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.trackFunctionCall("retrieveEvents", success: false)
                    self?.isLoading = false
                    if let idx = self?.messages.firstIndex(where: { $0.id == streamingId }) {
                        self?.messages[idx] = Message(
                            id: streamingId,
                            sender: .ai,
                            text: "Failed to retrieve data: \(error.localizedDescription)"
                        )
                    }
                    HapticsService.shared.streamEndedError()
                }
            }
        }
    }
    
    private func handleLogEvent(
        json: inout [String: Any],
        functionCall: FunctionCall,
        streamingId: UUID,
        webhookURL: String,
        openAIKey: String,
        rawArgs: String
    ) {
        // Apply device-local date & time
        applyLocalDateTime(to: &json)
        
        // Normalize numeric fields
        normalizeNumericFields(in: &json)
        
        let eventType = json["event_type"] as? String ?? ""
        
        // Validate event type
        guard !eventType.isEmpty else {
            showEventTypeError(streamingId: streamingId)
            return
        }
        
        // Check for duplicates
        let eventKey = generateEventKey(from: json)
        if loggedEvents.contains(eventKey) {
            print("⚠️ Skipping duplicate event: \(eventKey)")
            sendDuplicateResponse(
                streamingId: streamingId,
                openAIKey: openAIKey,
                webhookURL: webhookURL
            )
            return
        }
        
        // Mark as logged and send
        loggedEvents.insert(eventKey)
        WebhookService.sendEvent(data: json, webhookURL: webhookURL)
        trackFunctionCall("logEvent", success: true)
        
        // Send success response
        sendLogSuccessResponse(
            json: json,
            functionCall: functionCall,
            streamingId: streamingId,
            openAIKey: openAIKey,
            webhookURL: webhookURL,
            rawArgs: rawArgs
        )
    }
    
    private func handleRetrievalResponse(
        _ response: EventResponse,
        streamingId: UUID,
        openAIKey: String,
        webhookURL: String,
        functionCall: FunctionCall
    ) {
        // Transform the raw data into Event objects
        let _: [Event] = response.data?.compactMap { rawEventDict in
            return Event(
                id: rawEventDict["__ROW_NUMBER__"]?.value as? String ?? UUID().uuidString,
                eventType: "meal",
                date: rawEventDict["0"]?.value as? String ?? "",
                hour: rawEventDict["1"]?.value as? String ?? "",
                calories: Double(rawEventDict["5"]?.value as? String ?? "0"),
                proteins: Double(rawEventDict["3"]?.value as? String ?? "0"),
                fat: Double(rawEventDict["4"]?.value as? String ?? "0"),
                carbs: Double(rawEventDict["2"]?.value as? String ?? "0"),
                workout: nil, exercise: nil, sets: nil, reps: nil, weight: nil,
                category: nil, value: nil, currency: nil,
                comments: rawEventDict["6"]?.value as? String
            )
        } ?? []
        
        // Build a natural language summary of the retrieved data
        var summary = "Retrieved data:\n"
        
        if let metadata = response.metadata {
            if let aggregations = metadata.aggregations {
                if let totalCalories = aggregations.totalCalories {
                    summary += "Total calories: \(Int(totalCalories))\n"
                }
                if let avgCalories = aggregations.averageCalories {
                    summary += "Average calories: \(Int(avgCalories))\n"
                }
                if let totalValue = aggregations.totalValue {
                    summary += "Total expenses: \(totalValue)\n"
                }
            }
            summary += "Total records: \(metadata.count)\n"
        }
        
        // Build tool response messages for OpenAI
        let assistantToolCallMessage: [String: Any] = [
            "role": "assistant",
            "content": "",
            "tool_calls": [[
                "id": functionCall.id,
                "type": "function",
                "function": [
                    "name": functionCall.function.name,
                    "arguments": functionCall.function.arguments
                ]
            ]]
        ]
        
        let toolResultMessage: [String: Any] = [
            "role": "tool",
            "tool_call_id": functionCall.id,
            "name": functionCall.function.name,
            "content": summary
        ]
        
        // Continue conversation with retrieved data
        let cleanMessages = self.messages.filter {
            $0.id != streamingId && $0.text != Constants.SystemMessages.aiThinking
        }
        
        self.openAIService.sendMessageStreamWithRetry(
            messages: cleanMessages,
            apiKey: openAIKey,
            webhookURL: webhookURL,
            functionResponses: [assistantToolCallMessage, toolResultMessage],
            maxRetries: 2,
            onPartial: { [weak self] partial in
                DispatchQueue.main.async {
                    if let idx = self?.messages.firstIndex(where: { $0.id == streamingId }) {
                        self?.messages[idx] = Message(id: streamingId, sender: .ai, text: partial)
                        if !partial.isEmpty && partial != Constants.SystemMessages.aiThinking {
                            self?.saveConversation()
                        }
                    }
                    HapticsService.shared.streamTick()
                }
            },
            onFunctionCall: { _ in },
            onComplete: { [weak self] result in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    if case .failure(let error) = result {
                        print("❌ Streaming error: \(error)")
                        HapticsService.shared.streamEndedError()
                    } else {
                        self?.saveConversation()
                        HapticsService.shared.streamEndedSuccess()
                    }
                }
            }
        )
    }
    
    // MARK: - Helper Methods

    private func applyLocalDateTime(to json: inout [String: Any]) {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = .current
        dateFormatter.locale = .current
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let timeFormatter = DateFormatter()
        timeFormatter.calendar = .current
        timeFormatter.locale = .current
        timeFormatter.timeZone = .current
        timeFormatter.dateFormat = "HH:mm"
        
        json["date"] = dateFormatter.string(from: now)
        json["hour"] = timeFormatter.string(from: now)
    }

    private func normalizeNumericFields(in json: inout [String: Any]) {
        func toNumber(_ v: Any?) -> Any? {
            if let n = v as? NSNumber { return n }
            if let s = v as? String, let d = Double(s) { return d }
            return nil
        }
        
        let eventType = json["event_type"] as? String ?? ""
        
        switch eventType {
        case "meal":
            ["calories", "proteins", "fat", "carbs"].forEach { key in
                if let v = toNumber(json[key]) { json[key] = v }
            }
        case "expense":
            if let v = toNumber(json["value"]) { json["value"] = v }
        case "workout":
            ["sets", "reps", "weight"].forEach { key in
                if let v = toNumber(json[key]) { json[key] = v }
            }
        default:
            break
        }
    }

    private func generateEventKey(from json: [String: Any]) -> String {
        let eventType = json["event_type"] as? String ?? ""
        let comments = json["comments"] ?? ""
        let value = json["value"] ?? json["calories"] ?? json["workout"] ?? ""
        return "\(eventType)_\(comments)_\(value)"
    }

    private func showEventTypeError(streamingId: UUID) {
        DispatchQueue.main.async { [weak self] in
            self?.isLoading = false
            if let idx = self?.messages.firstIndex(where: { $0.id == streamingId }) {
                self?.messages[idx] = Message(
                    id: streamingId,
                    sender: .ai,
                    text: "I couldn't detect what type of event to log. Try again with meal/workout/expense."
                )
            }
            HapticsService.shared.streamEndedError()
        }
    }
    
    private func handleWebhookIfNeeded(from userPrompt: String) {
        guard let webhookURL = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.webhookURL),
              !webhookURL.isEmpty else {
            return
        }

        webhookService.processPrompt(prompt: userPrompt, webhookURL: webhookURL) { _ in
            // Optionally handle 200/400 responses later
        }
    }
    
    private func sendDuplicateResponse(
        streamingId: UUID,
        openAIKey: String,
        webhookURL: String
    ) {
        // This is your existing duplicate handling code, just moved to a method
        self.openAIService.sendMessageStreamWithRetry(
            messages: self.messages.filter { $0.id != streamingId && $0.text != Constants.SystemMessages.aiThinking },
            apiKey: openAIKey,
            webhookURL: webhookURL,
            functionResponses: [], // Empty - we're not acknowledging the duplicate
            maxRetries: 2,
            onPartial: { [weak self] partial in
                DispatchQueue.main.async {
                    if let idx = self?.messages.firstIndex(where: { $0.id == streamingId }) {
                        self?.messages[idx] = Message(id: streamingId, sender: .ai, text: partial)
                        if !partial.isEmpty && partial != Constants.SystemMessages.aiThinking {
                            self?.saveConversation()
                        }
                    }
                    HapticsService.shared.streamTick()
                }
            },
            onFunctionCall: { _ in },
            onComplete: { [weak self] result in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    if case .failure(let error) = result {
                        print("❌ Streaming error: \(error)")
                        HapticsService.shared.streamEndedError()
                    } else {
                        self?.saveConversation()
                        HapticsService.shared.streamEndedSuccess()
                    }
                }
            }
        )
    }
    
    private func sendLogSuccessResponse(
        json: [String: Any],
        functionCall: FunctionCall,
        streamingId: UUID,
        openAIKey: String,
        webhookURL: String,
        rawArgs: String
    ) {
        // Build assistant tool-call + tool result messages for the follow-up turn
        let assistantToolCallMessage: [String: Any] = [
            "role": "assistant",
            "content": "",  // Important: empty content when using tools
            "tool_calls": [[
                "id": functionCall.id,
                "type": "function",
                "function": [
                    "name": functionCall.function.name,
                    "arguments": rawArgs
                ]
            ]]
        ]

        let toolResultMessage: [String: Any] = [
            "role": "tool",
            "tool_call_id": functionCall.id,
            "name": functionCall.function.name,
            "content": "Event logged successfully on \(json["date"] ?? "") at \(json["hour"] ?? "")."
        ]

        // Filter out the thinking message and prepare clean history
        let cleanMessages = self.messages.filter {
            $0.id != streamingId && $0.text != Constants.SystemMessages.aiThinking
        }

        // Second streamed call to let the model wrap up in natural language
        self.openAIService.sendMessageStreamWithRetry(
            messages: cleanMessages,
            apiKey: openAIKey,
            webhookURL: webhookURL,
            functionResponses: [assistantToolCallMessage, toolResultMessage],
            maxRetries: 2,
            onPartial: { [weak self] partial in
                DispatchQueue.main.async {
                    if let idx = self?.messages.firstIndex(where: { $0.id == streamingId }) {
                        self?.messages[idx] = Message(id: streamingId, sender: .ai, text: partial)
                        if !partial.isEmpty && partial != Constants.SystemMessages.aiThinking {
                            self?.saveConversation()
                        }
                    }
                    HapticsService.shared.streamTick()
                }
            },
            onFunctionCall: { _ in
                // Usually no nested function calls, but if needed, handle here
            },
            onComplete: { [weak self] result in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    if case .failure(let error) = result,
                       let idx = self?.messages.firstIndex(where: { $0.id == streamingId }) {
                        let errorText = self?.formatError(error) ?? "An error occurred"
                        self?.messages[idx] = Message(id: streamingId, sender: .ai, text: errorText)
                        HapticsService.shared.streamEndedError()
                    } else {
                        self?.saveConversation()
                        HapticsService.shared.streamEndedSuccess()
                    }
                }
            }
        )
    }
    
    private func trackFunctionCall(_ name: String, success: Bool) {
        // Simple analytics for monitoring function usage
        print("📊 Function: \(name), Success: \(success), Timestamp: \(Date())")
        
        // In the future, you could:
        // - Send to analytics service
        // - Store usage statistics
        // - Monitor error rates
        // - Track most common user requests
    }

    private func removeThinkingMessage() {
        if let last = messages.last, last.text == Constants.SystemMessages.aiThinking {
            messages.removeLast()
        }
    }
}
