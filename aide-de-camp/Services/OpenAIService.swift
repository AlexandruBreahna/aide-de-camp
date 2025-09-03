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
              comments: "none"
            - Map common currency words/symbols to ISO codes (e.g., euros → EUR, $, usd → USD, lei → RON, pounds → GBP). If currency is unclear, leave it as a 3-letter best guess.
            - Default category to "outgoing" unless user explicitly indicates another (e.g., "income", "refund").

            IMPORTANT
            - Do not place units in numeric fields (only numbers). Put units/assumptions in "comments".
            - Prefer best-effort extraction/estimation over follow-up questions.
            """
        ]
        
        var chatMessages: [[String: Any]] = messages
            .filter { $0.text != Constants.SystemMessages.aiThinking }
            .map { m in ["role": m.isFromUser ? "user" : "assistant", "content": m.text] }
        
        // append assistant tool_call message + tool result, if any
        chatMessages.append(contentsOf: functionResponses)
        
        let messagesPayload: [[String: Any]] = [systemMessage] + chatMessages
        
        let tools: [[String: Any]] = [[
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
        ]]
        
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
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        session.dataTask(with: request).resume()
    }
}

// MARK: - Streaming Delegate

// Services/OpenAIService.swift

private class StreamingSessionDelegate: NSObject, URLSessionDataDelegate {
    private let webhookURL: String
    private let onPartial: (String) -> Void
    private let onFunctionCall: ((FunctionCall) -> Void)?
    private let onComplete: (Result<Void, Error>) -> Void

    private var textBuffer = ""

    // Accumulator for tool-calls during streaming
    private struct ToolAcc {
        var id: String?
        var name: String?
        var arguments: String = ""
    }
    private var toolAccumulators: [Int: ToolAcc] = [:] // keyed by 'index'

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

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunkText = String(data: data, encoding: .utf8) else { return }

        chunkText.enumerateLines { rawLine, _ in
            guard rawLine.hasPrefix("data: ") else { return }
            let payload = rawLine.dropFirst(6)
            if payload == "[DONE]" {
                self.onComplete(.success(()))
                return
            }
            guard let jsonData = payload.data(using: .utf8) else { return }

            do {
                let sse = try JSONDecoder().decode(StreamChunk.self, from: jsonData)
                if let delta = sse.choices.first?.delta {
                    if let content = delta.content {
                        self.textBuffer += content
                        self.onPartial(self.textBuffer)
                    }
                    if let toolDeltas = delta.toolCalls {
                        for d in toolDeltas {
                            let idx = d.index ?? 0
                            var acc = self.toolAccumulators[idx, default: ToolAcc()]
                            if let id = d.id { acc.id = id }
                            if let name = d.function.name { acc.name = name }
                            if let args = d.function.arguments { acc.arguments += args }
                            self.toolAccumulators[idx] = acc
                        }
                    }
                }

                // IMPORTANT: modern API uses "tool_calls" (plural) when the assistant finishes emitting a tool call.  [oai_citation:4‡OpenAI Cookbook](https://cookbook.openai.com/examples/how_to_call_functions_with_chat_models)
                if let finish = sse.choices.first?.finishReason, finish == "tool_calls" {
                    for (_, acc) in self.toolAccumulators {
                        guard let id = acc.id, let name = acc.name else { continue }
                        let fc = FunctionCall(
                            id: id,
                            function: .init(name: name, arguments: acc.arguments)
                        )
                        self.onFunctionCall?(fc)
                    }
                }
            } catch {
                self.onComplete(.failure(error))
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error { onComplete(.failure(error)) }
    }
}

// MARK: - Streaming DTOs

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
        let delta: Delta
        let finishReason: String?
        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }
    let choices: [Choice]
}

private struct ToolCallDelta: Decodable {
    struct Fn: Decodable {
        let name: String?
        let arguments: String?
    }
    let id: String?
    let index: Int?
    let function: Fn
    // 'type' may exist but not needed here
}
