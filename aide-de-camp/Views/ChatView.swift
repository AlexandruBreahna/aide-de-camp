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
                                MessageBubbleView(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 80) // room for input bar inset
                        // Ensure the whole area is tappable for dismissing keyboard
                        .contentShape(Rectangle())
                    }
                    // 1) Dismiss keyboard as you scroll (iOS 16+)
                    .scrollDismissesKeyboard(.interactively)
                    // 2) Tapping anywhere in the chat history clears focus
                    .simultaneousGesture(TapGesture().onEnded {
                        isInputFocused = false
                    })
                    .onChange(of: viewModel.messages.count, initial: false) { _, _ in
                        if let last = viewModel.messages.last {
                            scrollProxy.scrollTo(last.id, anchor: .bottom)
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
