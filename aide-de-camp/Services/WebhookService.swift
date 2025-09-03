//
//  WebhookService.swift
//  aide-de-camp
//
//  Created by Alexander Eckhart on 30.08.25.
//

import Foundation

final class WebhookService {
    static let shared = WebhookService()

    /// Sends the entire prompt to the webhook if it contains keywords like "log", "record", "track"
    func processPrompt(prompt: String, webhookURL: String, completion: @escaping (Bool) -> Void) {
        let triggerWords = ["log", "record", "track", "save", "add"]

        guard triggerWords.contains(where: { prompt.lowercased().contains($0) }) else {
            completion(false)
            return
        }

        guard let url = URL(string: webhookURL) else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = [
            "prompt": prompt
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            completion(false)
            return
        }

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                completion(true)
            } else {
                completion(false)
            }
        }.resume()
    }

    static func sendEvent(data: [String: Any], webhookURL: String) {
        guard let url = URL(string: webhookURL) else {
            print("❌ Webhook URL is missing or invalid.")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let payload = try JSONSerialization.data(withJSONObject: data, options: [])
            request.httpBody = payload
            print("📦 Sending payload to webhook: \(String(data: payload, encoding: .utf8) ?? "Invalid JSON")")
        } catch {
            print("❌ Failed to encode JSON: \(error)")
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Webhook request failed: \(error)")
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    print("✅ Webhook response code: 200 OK")
                } else {
                    print("⚠️ Webhook responded with code: \(httpResponse.statusCode)")
                    if let data = data, let body = String(data: data, encoding: .utf8) {
                        print("⚠️ Webhook response body: \(body)")
                    }
                }
            }
        }.resume()
    }
}
