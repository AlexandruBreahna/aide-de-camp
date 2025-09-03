//
//  SettingsDrawerView.swift
//  aide-de-camp
//
//  Created by Alexander Eckhart on 30.08.25.
//

import SwiftUI

struct SettingsDrawerView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var originalKey: String = ""
    @State private var originalURL: String = ""
    @State private var hasChanges: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("OpenAI API Key")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    SecureField("Enter your OpenAI API Key", text: $viewModel.openAIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .onChange(of: viewModel.openAIKey, initial: false) { _, _ in detectChanges() }
                }

                Section {
                    Text("Make Webhook URL")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("Enter your Make Webhook URL", text: $viewModel.webhookURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .onChange(of: viewModel.webhookURL, initial: false) { _, _ in detectChanges() }
                }

                Section {
                    Button("Save Settings") {
                        viewModel.save()
                        dismiss()
                    }
                    .disabled(!hasChanges)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                let settings = Settings.load()
                viewModel.openAIKey = settings.openAIKey
                viewModel.webhookURL = settings.webhookURL
                originalKey = viewModel.openAIKey
                originalURL = viewModel.webhookURL
                hasChanges = false
            }
        }
    }

    private func detectChanges() {
        hasChanges = (viewModel.openAIKey != originalKey || viewModel.webhookURL != originalURL)
    }
}
