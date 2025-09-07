//
//  OpenAIService.swift
//  aide-de-camp
//
//  Created by Alexander Eckhart on 30.08.25.
//

import Foundation

// Services/OpenAIService.swift
final class OpenAIService {
    private let endpoint = "https://api.openai.com/v1/chat/completions"
    private let model = "gpt-4.1" // OK per current docs.  [oai_citation:2‡OpenAI Platform](https://platform.openai.com/docs/models/gpt-4.1?utm_source=chatgpt.com) [oai_citation:3‡OpenAI](https://openai.com/index/gpt-4-1/?utm_source=chatgpt.com)
    
    func sendMessageStream(
        messages: [Message],
        apiKey: String,
        webhookURL: String,
        functionResponses: [[String: Any]] = [], // ← allow nested objects (tool_calls)
        onPartial: @escaping (String) -> Void,
        onFunctionCall: ((FunctionCall) -> Void)? = nil,
        onComplete: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let url = URL(string: endpoint) else {
            onComplete(.failure(NSError(domain: "Invalid OpenAI URL", code: 0)))
            return
        }
        
        let systemMessage: [String: String] = [
            "role": "system",
            "content": """
            You are a helpful assistant for matters related to health, fitness, nutrition, and finances. You offer practical advice on the aforementioned domains and ONLY when the user requests, you call the provided function to log a meal, workout, or expense.

            CRITICAL RULES FOR LOGGING:
            - NEVER re-log items that have already been logged in this conversation
            - Only log NEW items explicitly mentioned in the CURRENT user message
            - If a user mentions a price for something already logged, only log the expense, NOT the item again
            - Each function call should represent ONE unique event that hasn't been logged yet
            - When in doubt, ask for clarification rather than logging duplicates

            GENERAL RULES
            - Always include: "event_type", "date", and "hour" in the function arguments. Use your best guess, but the client will overwrite date/hour with the device's time.
            - Keep arguments strictly JSON-serializable primitives (strings/numbers). Put any units or assumptions in "comments". Prefer whole numbers where reasonable.
            - If information is missing, infer sensible defaults rather than asking follow-up questions.

            MEALS
            - Parse everyday descriptions like "two fried eggs and 250ml of coke".
            - Estimate numeric values for: calories (kcal), proteins (g), fat (g), carbs (g).
            - Convert quantities (e.g., 250ml soda, two eggs, 100g chicken). Place assumptions in "comments".

            WORKOUTS
            - Users may write: "I trained chest at the horizontal bench, did 4 sets of 12 reps each. I struggled with the last set." → Produce:
              event_type: "workout",
              workout: "chest",
              exercise: "horizontal bench",
              sets: 4,
              reps: 12,
              comments: "I struggled with the last set."
            - Users may also include weight, e.g., "I did 4 sets of 12 with an average weight of 80kg" → include:
              weight: 80
            - Extract muscle group or workout type to "workout" (e.g., chest, legs, cardio). Extract equipment/movement to "exercise" (e.g., horizontal bench, barbell squat, treadmill run).
            - If multiple exercises are mentioned, prefer the primary one; put extras into "comments".

            EXPENSES
            - Users may write: "I just spent 40 euros on a meal and a drink in the city." → Produce:
              event_type: "expense",
              category: "outgoing",
              value: 40,
              currency: "EUR",
              comments: "meal and drink in the city"
            - Map common currency words/symbols to ISO codes (e.g., euros → EUR, $, usd → USD, lei → RON, pounds → GBP). If currency is unclear, leave it as a 3-letter best guess.
            - Default category to "outgoing" unless user explicitly indicates another (e.g., "income", "refund").

            IMPORTANT
            - Do not place units in numeric fields (only numbers). Put units/assumptions in "comments".
            - Prefer best-effort extraction/estimation over follow-up questions.
            - Track conversation context to avoid duplicate logging.
            
            RETRIEVAL RULES
            - When users ask about their logged data, use the retrieveEvents function
            - Convert natural language dates to YYYY-MM-DD format:
              * "today" → current date
              * "yesterday" → current date - 1
              * "this week" → date_from: start of week, date_to: today
              * "last month" → appropriate date range
            - Choose appropriate aggregation based on question:
              * "How many calories today?" → aggregation: "sum", event_type: "meal"
              * "Show me my workouts this week" → aggregation: "details", event_type: "workout"
              * "What's my average daily expense?" → aggregation: "average", event_type: "expense"
            - Never retrieve the same data twice in one conversation unless explicitly asked
            - Present data in a natural, conversational way
            - For comparisons, make multiple retrieveEvents calls with different date ranges
            """
        ]
        
        var chatMessages: [[String: Any]] = messages
            .filter { $0.text != Constants.SystemMessages.aiThinking }
            .map { m in ["role": m.isFromUser ? "user" : "assistant", "content": m.text] }
        
        // append assistant tool_call message + tool result, if any
        chatMessages.append(contentsOf: functionResponses)
        
        let messagesPayload: [[String: Any]] = [systemMessage] + chatMessages
        
        let tools: [[String: Any]] = [
            [
                "type": "function",
                "function": [
                    "name": "logEvent",
                    "description": "Logs a meal, workout or expense to Google Sheets via Make webhook.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "event_type": ["type": "string", "enum": ["meal", "workout", "expense"]],
                            "date": ["type": "string", "description": "YYYY-MM-DD"],
                            "hour": ["type": "string", "description": "HH:mm"],
                            "calories": ["type": "number"],
                            "proteins": ["type": "number"],
                            "fat": ["type": "number"],
                            "carbs": ["type": "number"],
                            "workout": ["type": "string"],
                            "exercise": ["type": "string"],
                            "sets": ["type": "number"],
                            "reps": ["type": "number"],
                            "weight": ["type": "number"],
                            "category": ["type": "string"],
                            "value": ["type": "number"],
                            "currency": ["type": "string"],
                            "comments": ["type": "string"]
                        ],
                        "required": ["event_type", "date", "hour"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "retrieveEvents",
                    "description": "Retrieves logged meals, workouts or expenses from the database with optional filtering and aggregation.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "event_type": [
                                "type": "string",
                                "enum": ["meal", "workout", "expense"],
                                "description": "Optional: filter by event type"
                            ],
                            "date_from": [
                                "type": "string",
                                "description": "Optional: start date (YYYY-MM-DD) for filtering"
                            ],
                            "date_to": [
                                "type": "string",
                                "description": "Optional: end date (YYYY-MM-DD) for filtering"
                            ],
                            "aggregation": [
                                "type": "string",
                                "enum": ["sum", "average", "count", "details"],
                                "description": "Type of data to return: sum totals, average values, count of entries, or full details"
                            ],
                            "limit": [
                                "type": "number",
                                "description": "Optional: maximum number of records to return (default 100)"
                            ]
                        ],
                        "required": []
                    ]
                ]
            ]
        ]
        
        let body: [String: Any] = [
            "model": model,
            "messages": messagesPayload,
            "temperature": 0.7,
            "stream": true,
            "tools": tools,
            "tool_choice": "auto"
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept") // streaming SSE hint
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            onComplete(.failure(error)); return
        }
        
        let delegate = StreamingSessionDelegate(
            webhookURL: webhookURL,
            onPartial: onPartial,
            onFunctionCall: onFunctionCall,
            onComplete: onComplete
        )
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        delegate.setSession(session) // Pass session reference for cleanup
        
        let task = session.dataTask(with: request)
        task.resume()
    }
    
    func sendMessageStreamWithRetry(
        messages: [Message],
        apiKey: String,
        webhookURL: String,
        functionResponses: [[String: Any]] = [],
        maxRetries: Int = 2,
        onPartial: @escaping (String) -> Void,
        onFunctionCall: ((FunctionCall) -> Void)? = nil,
        onComplete: @escaping (Result<Void, Error>) -> Void
    ) {
        var retryCount = 0
        
        func attemptRequest() {
            sendMessageStream(
                messages: messages,
                apiKey: apiKey,
                webhookURL: webhookURL,
                functionResponses: functionResponses,
                onPartial: onPartial,
                onFunctionCall: onFunctionCall,
                onComplete: { result in
                    switch result {
                    case .success:
                        onComplete(.success(()))
                    case .failure(let error):
                        let nsError = error as NSError
                        
                        // Determine if error is retryable
                        let isRetryable = self.isRetryableError(nsError)
                        
                        if isRetryable && retryCount < maxRetries {
                            retryCount += 1
                            // Exponential backoff: 1s, 2s, 4s...
                            let delay = pow(2.0, Double(retryCount - 1))
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                attemptRequest()
                            }
                        } else {
                            onComplete(.failure(error))
                        }
                    }
                }
            )
        }
        
        attemptRequest()
    }

    private func isRetryableError(_ error: NSError) -> Bool {
        // Network errors
        if error.domain == NSURLErrorDomain {
            let retryableCodes = [
                NSURLErrorTimedOut,
                NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorDNSLookupFailed,
                NSURLErrorNotConnectedToInternet,
                NSURLErrorInternationalRoamingOff
            ]
            return retryableCodes.contains(error.code)
        }
        
        // OpenAI API errors (rate limits, server errors)
        if error.domain == "OpenAI API Error" {
            let retryableStatusCodes = [429, 500, 502, 503, 504] // Rate limit and server errors
            return retryableStatusCodes.contains(error.code)
        }
        
        return false
    }
}

// MARK: - Streaming Delegate

private class StreamingSessionDelegate: NSObject, URLSessionDataDelegate {
    private let webhookURL: String
    private let onPartial: (String) -> Void
    private let onFunctionCall: ((FunctionCall) -> Void)?
    private let onComplete: (Result<Void, Error>) -> Void
    
    private var textBuffer = ""
    private var dataBuffer = Data() // Buffer for incomplete SSE chunks
    
    // Accumulator for tool-calls during streaming
    private struct ToolAcc {
        var id: String?
        var name: String?
        var arguments: String = ""
    }
    private var toolAccumulators: [Int: ToolAcc] = [:] // keyed by 'index'
    
    // Add weak reference to session to properly clean up
    private weak var session: URLSession?
    
    init(
        webhookURL: String,
        onPartial: @escaping (String) -> Void,
        onFunctionCall: ((FunctionCall) -> Void)?,
        onComplete: @escaping (Result<Void, Error>) -> Void
    ) {
        self.webhookURL = webhookURL
        self.onPartial = onPartial
        self.onFunctionCall = onFunctionCall
        self.onComplete = onComplete
    }
    
    func setSession(_ session: URLSession) {
        self.session = session
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Append new data to buffer
        dataBuffer.append(data)
        
        // Process complete lines from buffer
        guard let bufferString = String(data: dataBuffer, encoding: .utf8) else { return }
        let lines = bufferString.components(separatedBy: "\n")
        
        // Keep the last incomplete line in buffer
        if let lastLine = lines.last, !lastLine.isEmpty && !bufferString.hasSuffix("\n") {
            dataBuffer = lastLine.data(using: .utf8) ?? Data()
        } else {
            dataBuffer = Data()
        }
        
        // Process all complete lines
        for (index, line) in lines.enumerated() {
            // Skip the last line if it's incomplete
            if index == lines.count - 1 && !bufferString.hasSuffix("\n") {
                break
            }
            
            processLine(line)
        }
    }
    
    private func processLine(_ line: String) {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Skip empty lines and non-data lines
        guard !trimmedLine.isEmpty else { return }
        guard trimmedLine.hasPrefix("data: ") else { return }
        
        let payload = String(trimmedLine.dropFirst(6))
        
        if payload == "[DONE]" {
            // Process any remaining tool calls before completing
            finalizeToolCalls()
            cleanup()
            onComplete(.success(()))
            return
        }
        
        guard let jsonData = payload.data(using: .utf8) else { return }
        
        do {
            let sse = try JSONDecoder().decode(StreamChunk.self, from: jsonData)
            
            if let delta = sse.choices.first?.delta {
                // Handle content streaming
                if let content = delta.content {
                    textBuffer += content
                    onPartial(textBuffer)
                }
                
                // Handle tool call streaming
                if let toolDeltas = delta.toolCalls {
                    for toolDelta in toolDeltas {
                        let idx = toolDelta.index ?? 0
                        var acc = toolAccumulators[idx, default: ToolAcc()]
                        
                        if let id = toolDelta.id { acc.id = id }
                        if let name = toolDelta.function?.name { acc.name = name }
                        if let args = toolDelta.function?.arguments { acc.arguments += args }
                        
                        toolAccumulators[idx] = acc
                    }
                }
            }
            
            // Check for finish_reason
            if let finishReason = sse.choices.first?.finishReason {
                if finishReason == "tool_calls" {
                    finalizeToolCalls()
                    // Don't complete here - wait for [DONE]
                }
                // "stop" and "length" are also followed by [DONE], so we wait
            }
            
        } catch {
            // Log parsing errors but don't fail the stream
            print("⚠️ Failed to parse SSE chunk: \(error)")
            // Continue processing other chunks
        }
    }
    
    private func finalizeToolCalls() {
        for (_, acc) in toolAccumulators {
            guard let id = acc.id, let name = acc.name else { continue }
            let fc = FunctionCall(
                id: id,
                function: .init(name: name, arguments: acc.arguments)
            )
            onFunctionCall?(fc)
        }
        toolAccumulators.removeAll()
    }
    
    private func cleanup() {
        session?.invalidateAndCancel()
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            // Check if it's a cancellation we initiated (not an error)
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                // This is expected when we call cleanup() after [DONE]
                return
            }
            cleanup()
            onComplete(.failure(error))
        }
        // Success case is handled by [DONE] message
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // Check for valid response
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode >= 400 {
                cleanup()
                onComplete(.failure(NSError(
                    domain: "OpenAI API Error",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]
                )))
                completionHandler(.cancel)
                return
            }
        }
        completionHandler(.allow)
    }
}

// MARK: - Streaming DTOs

// Update the StreamChunk struct to match current OpenAI API
private struct StreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
            let toolCalls: [ToolCallDelta]?
            
            enum CodingKeys: String, CodingKey {
                case content
                case toolCalls = "tool_calls"
            }
        }
        
        let delta: Delta?
        let finishReason: String?
        let index: Int
        
        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
            case index
        }
    }
    let choices: [Choice]
}

private struct ToolCallDelta: Decodable {
    struct Function: Decodable {
        let name: String?
        let arguments: String?
    }
    
    let id: String?
    let index: Int?
    let type: String?
    let function: Function?
}
