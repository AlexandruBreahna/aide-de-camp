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

    private var cancellables = Set<AnyCancellable>()
    private let openAIService = OpenAIService()
    private let webhookService = WebhookService()

    init() {}

    // ViewModels/ChatViewModel.swift
    func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let openAIKey = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.openAIKey),
              !openAIKey.isEmpty else {
            alertMessage = Constants.SystemMessages.missingAPIKey
            return
        }

        guard let webhookURL = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.webhookURL),
              !webhookURL.isEmpty else {
            alertMessage = Constants.SystemMessages.missingWebhookURL
            return
        }

        // 1) append user message + show placeholder
        let userMessage = Message(sender: .user, text: trimmed)
        appendMessage(userMessage)
        inputText = ""
        isLoading = true

        let streamingMessage = Message(sender: .ai, text: Constants.SystemMessages.aiThinking)
        appendMessage(streamingMessage)
        let streamingId = streamingMessage.id
        
        HapticsService.shared.streamBegan()

        // 2) first turn: stream assistant
        openAIService.sendMessageStream(
            messages: messages,
            apiKey: openAIKey,
            webhookURL: webhookURL,
            functionResponses: [], // none yet
            onPartial: { [weak self] partial in
                DispatchQueue.main.async {
                    if let idx = self?.messages.firstIndex(where: { $0.id == streamingId }) {
                        self?.messages[idx] = Message(id: streamingId, sender: .ai, text: partial)
                    }
                    HapticsService.shared.streamTick()
                }
            },
            onFunctionCall: { [weak self] functionCall in
                guard let self = self else { return }

                // 1) Parse model arguments (may or may not include date/hour)
                let rawArgs = functionCall.function.arguments
                let argsData = rawArgs.data(using: .utf8) ?? Data()
                var json = (try? JSONSerialization.jsonObject(with: argsData)) as? [String: Any] ?? [:]

                // 2) Force device-local date & time (override whatever the model sent)
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
                
                // Ensure numbers are numeric (some models may send strings like "250")
                func toNumber(_ v: Any?) -> Any? {
                    if let n = v as? NSNumber { return n }
                    if let s = v as? String, let d = Double(s) { return d }
                    return nil
                }

                if (json["event_type"] as? String) == "meal" {
                    if let v = toNumber(json["calories"]) { json["calories"] = v }
                    if let v = toNumber(json["proteins"]) { json["proteins"] = v }
                    if let v = toNumber(json["fat"]) { json["fat"] = v }
                    if let v = toNumber(json["carbs"]) { json["carbs"] = v }
                }
                if (json["event_type"] as? String) == "expense" {
                    if let v = toNumber(json["value"]) { json["value"] = v }
                }
                if (json["event_type"] as? String) == "workout" {
                    if let v = toNumber(json["sets"]) { json["sets"] = v }
                    if let v = toNumber(json["reps"]) { json["reps"] = v }
                    if let v = toNumber(json["weight"]) { json["weight"] = v }
                }

                // Basic guard for required fields
                guard json["event_type"] as? String != nil else {
                    DispatchQueue.main.async {
                        self.isLoading = false
                        if let idx = self.messages.firstIndex(where: { $0.id == streamingId }) {
                            self.messages[idx] = Message(
                                id: streamingId,
                                sender: .ai,
                                text: "I couldn’t detect what type of event to log. Try again with meal/workout/expense."
                            )
                        }
                    }
                    return
                }

                // 3) Send to webhook ONCE here
                guard let webhookURL = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.webhookURL),
                      !webhookURL.isEmpty else { return }
                WebhookService.sendEvent(data: json, webhookURL: webhookURL)

                // 4) Build assistant tool-call + tool result messages for the follow-up turn
                let assistantToolCallMessage: [String: Any] = [
                    "role": "assistant",
                    "content": "",
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

                // 5) Second streamed call to let the model wrap up in natural language
                self.openAIService.sendMessageStream(
                    messages: self.messages,
                    apiKey: UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.openAIKey) ?? "",
                    webhookURL: webhookURL,
                    functionResponses: [assistantToolCallMessage, toolResultMessage],
                    onPartial: { [weak self] partial in
                        DispatchQueue.main.async {
                            if let idx = self?.messages.firstIndex(where: { $0.id == streamingId }) {
                                self?.messages[idx] = Message(id: streamingId, sender: .ai, text: partial)
                            }
                            HapticsService.shared.streamTick()
                        }
                    },
                    onFunctionCall: { _ in },
                    onComplete: { [weak self] result in
                        DispatchQueue.main.async {
                            self?.isLoading = false
                            if case .failure(let error) = result,
                               let idx = self?.messages.firstIndex(where: { $0.id == streamingId }) {
                                self?.messages[idx] = Message(id: streamingId, sender: .ai, text: "Error: \(error.localizedDescription)")
                                // + Haptics: error
                                HapticsService.shared.streamEndedError()
                            } else {
                                // + Haptics: success
                                HapticsService.shared.streamEndedSuccess()
                            }
                        }
                    }
                )
            },
            onComplete: { [weak self] result in
                DispatchQueue.main.async {
                    // If there was NO tool-call path, finish here
                    if case .failure(let error) = result {
                        if let idx = self?.messages.lastIndex(where: { $0.id == streamingMessage.id }) {
                            self?.messages[idx] = Message(id: streamingMessage.id, sender: .ai, text: "Error: \(error.localizedDescription)")
                        }
                        // + Haptics: error
                        HapticsService.shared.streamEndedError()
                    } else {
                        // + Haptics: success
                        HapticsService.shared.streamEndedSuccess()
                    }
                    // If a tool call happened, the second request above will flip isLoading to false.
                    if self?.isLoading == true && (self?.messages.last?.text != Constants.SystemMessages.aiThinking) {
                        self?.isLoading = false
                    }
                }
            }
        )
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

    private func appendMessage(_ message: Message) {
        messages.append(message)

        if messages.count > Constants.maxMessageCount {
            messages.removeFirst(messages.count - Constants.maxMessageCount)
        }
    }

    private func removeThinkingMessage() {
        if let last = messages.last, last.text == Constants.SystemMessages.aiThinking {
            messages.removeLast()
        }
    }

    func startNewSession() {
        messages.removeAll()
    }
}
