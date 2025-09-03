//
//  SettingsViewModel.swift
//  aide-de-camp
//
//  Created by Alexander Eckhart on 30.08.25.
//

import Foundation
import Combine

final class SettingsViewModel: ObservableObject {
    @Published var openAIKey: String = ""
    @Published var webhookURL: String = ""
    @Published var showAlert: Bool = false
    @Published var alertMessage: String = ""

    init() {
        let settings = Settings.load()
        self.openAIKey = settings.openAIKey
        self.webhookURL = settings.webhookURL
    }

    func save() {
        let newSettings = Settings(openAIKey: openAIKey, webhookURL: webhookURL)

        if !newSettings.isValid() {
            alertMessage = "Both the OpenAI Key and Webhook URL must be filled in."
            showAlert = true
            return
        }

        newSettings.save()
        alertMessage = "Settings saved successfully."
        showAlert = true
    }
}
