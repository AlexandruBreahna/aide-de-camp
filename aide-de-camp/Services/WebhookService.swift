//
//  WebhookService.swift
//  aide-de-camp
//
//  Created by Alexander Eckhart on 30.08.25.
//

import Foundation

final class WebhookService {
    static let shared = WebhookService()
    private var pendingRequests: Set<String> = []
    
    enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }
    
    enum WebhookError: Error, LocalizedError {
        case invalidURL
        case invalidResponse
        case decodingError
        case serverError(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid webhook URL"
            case .invalidResponse: return "Invalid server response"
            case .decodingError: return "Failed to decode response"
            case .serverError(let msg): return msg
            }
        }
    }
    
    // MARK: - Generic Request Executor following Apple's URLSession best practices
    func executeRequest(
        method: HTTPMethod,
        operation: String,
        filters: [String: Any]? = nil,
        data: [String: Any]? = nil,
        webhookURL: String,
        completion: @escaping (Result<EventResponse, Error>) -> Void
    ) {
        guard let url = URL(string: webhookURL) else {
            completion(.failure(WebhookError.invalidURL))
            return
        }
        
        let filterString = filters?.map { "\($0.key):\($0.value)" }.joined(separator: ",") ?? "none"
            let requestSignature = "\(method.rawValue)_\(operation)_\(filterString)"
            
            guard !pendingRequests.contains(requestSignature) else {
                print("⚠️ Duplicate request in progress, skipping")
                return
            }
            pendingRequests.insert(requestSignature)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        // Build request payload
        let requestId = UUID().uuidString
        var payload: [String: Any] = [
            "method": method.rawValue,
            "operation": operation,
            "request_id": requestId
        ]
        
        if let filters = filters {
            payload["filters"] = filters
        }
        
        if let data = data {
            payload["data"] = data
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            print("📤 Webhook request: \(operation) with ID: \(requestId)")
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            defer {
                DispatchQueue.main.async {
                    self?.pendingRequests.remove(requestSignature)
                }
            }
            if let error = error {
                print("❌ Webhook request failed: \(error)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(WebhookError.invalidResponse))
                return
            }
            
            print("📥 Webhook response code: \(httpResponse.statusCode)")
            
            guard let data = data else {
                completion(.failure(WebhookError.invalidResponse))
                return
            }
            
            // Parse response
            do {
                let eventResponse = try JSONDecoder().decode(EventResponse.self, from: data)
                
                if eventResponse.success {
                    completion(.success(eventResponse))
                } else {
                    let errorMsg = eventResponse.error ?? "Unknown error"
                    completion(.failure(WebhookError.serverError(errorMsg)))
                }
            } catch {
                print("❌ Failed to decode response: \(error)")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("📥 Raw response: \(jsonString)")
                }
                completion(.failure(WebhookError.decodingError))
            }
        }.resume()
    }
    
    // MARK: - Legacy support for existing log functionality
    static func sendEvent(data: [String: Any], webhookURL: String) {
        WebhookService.shared.executeRequest(
            method: .post,
            operation: "create",
            filters: nil,
            data: data,
            webhookURL: webhookURL
        ) { result in
            switch result {
            case .success(let response):
                print("✅ Event logged successfully: \(response.requestId ?? "no-id")")
            case .failure(let error):
                print("❌ Failed to log event: \(error)")
            }
        }
    }
    
    // MARK: - Deprecated - kept for compatibility
    func processPrompt(prompt: String, webhookURL: String, completion: @escaping (Bool) -> Void) {
        // This method is no longer used but kept for compatibility
        completion(false)
    }
}
