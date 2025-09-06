//  ChatView.swift
//  aide-de-camp
//
//  Created by Alexander Eckhart on 30.08.25.
//

import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @FocusState private var isInputFocused: Bool
    @State private var showSettings = false
    @State private var settingsVM: SettingsViewModel? = nil

    var body: some View {
        ZStack {
            Color.clear
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HeaderView(onNewSession: viewModel.startNewSession) {
                    isInputFocused = false
                    showSettings.toggle()
                }

                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 4) {
                                    MessageBubbleView(message: message)
                                        .id(message.id)
                                    
                                    // Retry button for error messages
                                    if !message.isFromUser && (message.text.starts(with: "Error:") || message.text.starts(with: "Network error") || message.text.starts(with: "No internet")) {
                                        Button(action: {
                                            viewModel.retryLastMessage()
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.clockwise")
                                                    .font(.system(size: 12))
                                                Text("Retry")
                                                    .font(.caption)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.blue.opacity(0.1))
                                            .foregroundColor(.blue)
                                            .cornerRadius(12)
                                        }
                                        .padding(.horizontal)
                                        .disabled(viewModel.isLoading)
                                    }
                                }
                            }
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 80)
                        .contentShape(Rectangle())
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .simultaneousGesture(TapGesture().onEnded {
                        isInputFocused = false
                    })
                    .onAppear {
                        if let lastMessage = viewModel.messages.last {
                            scrollProxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                    // Watch for new messages being added
                    .onChange(of: viewModel.messages.count, initial: false) { _, _ in
                        if let last = viewModel.messages.last {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                scrollProxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    // Watch for loading state changes (when AI finishes responding)
                    .onChange(of: viewModel.isLoading, initial: false) { oldValue, newValue in
                        // When loading finishes (true -> false), scroll to bottom
                        if oldValue == true && newValue == false {
                            if let last = viewModel.messages.last {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        scrollProxy.scrollTo(last.id, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

        .onAppear {
            // Autofocus on load
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isInputFocused = true
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: { settingsVM = nil }) {
            // Create the VM only when the sheet opens
            let vm = settingsVM ?? SettingsViewModel()
            SettingsDrawerView(viewModel: vm)
                .onAppear { settingsVM = vm }
                .presentationDetents([.medium])
        }
        .onChange(of: showSettings) { _, isShown in
            if !isShown {
                // Return focus to input after closing settings
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isInputFocused = true
                }
            }
        }
        .alert(item: Binding(
            get: { viewModel.alertMessage.map { IdentifiedAlert(message: $0) } },
            set: { _ in viewModel.alertMessage = nil }
        )) { identified in
            Alert(
                title: Text("Notice"),
                message: Text(identified.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .safeAreaInset(edge: .bottom) {
            InputBarView(
                text: $viewModel.inputText,
                isLoading: viewModel.isLoading,
                onSend: viewModel.sendMessage,
                isInputFocused: $isInputFocused
            )
        }
    }
}

private struct IdentifiedAlert: Identifiable {
    let id = UUID()
    let message: String
}
