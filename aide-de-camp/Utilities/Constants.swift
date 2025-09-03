//
//  Constants.swift
//  aide-de-camp
//
//  Created by Alexander Eckhart on 30.08.25.
//

import Foundation

enum Constants {
    static let maxMessageCount = 30

    // UserDefaults keys for stored settings
    enum UserDefaultsKeys {
        static let openAIKey = "openAIKey"
        static let webhookURL = "webhookURL"
    }

    // Placeholder text and system messages
    struct SystemMessages {
        static let missingAPIKey = "Please enter your OpenAI API key in settings."
        static let missingWebhookURL = "Please enter your Make webhook URL in settings."
        static let aiThinking = "Thinking..."
    }
}
