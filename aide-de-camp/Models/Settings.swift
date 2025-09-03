//
//  Settings.swift
//  aide-de-camp
//
//  Created by Alexander Eckhart on 30.08.25.
//

import Foundation

struct Settings {
    var openAIKey: String
    var webhookURL: String

    static func load() -> Settings {
        let key = KeychainStore.get(Constants.UserDefaultsKeys.openAIKey)
        let url = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.webhookURL) ?? ""
        return Settings(openAIKey: key, webhookURL: url)
    }

    func save() {
        KeychainStore.set(openAIKey, for: Constants.UserDefaultsKeys.openAIKey)
        UserDefaults.standard.set(webhookURL, forKey: Constants.UserDefaultsKeys.webhookURL)
    }

    func isValid() -> Bool {
        !openAIKey.trimmingCharacters(in: .whitespaces).isEmpty &&
        !webhookURL.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
