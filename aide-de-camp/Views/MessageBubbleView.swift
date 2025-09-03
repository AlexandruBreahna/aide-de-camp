//
//  MessageBubbleView.swift
//  aide-de-camp
//
//  Created by Alexander Eckhart on 30.08.25.
//

import SwiftUI

struct MessageBubbleView: View {
    let message: Message

    var body: some View {
        HStack {
            if message.isFromUser {
                Spacer()
            }

            if message.text == Constants.SystemMessages.aiThinking {
                TypingIndicatorView()
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(UIColor.systemGray6))
                    )
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: .leading)
            } else {
                Text(message.text)
                    .padding(12)
                    .foregroundColor(message.isFromUser ? .white : .primary)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(message.isFromUser ? Color.blue : Color(UIColor.systemGray6))
                    )
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: message.isFromUser ? .trailing : .leading)
            }

            if !message.isFromUser {
                Spacer()
            }
        }
        .padding(.horizontal)
        .transition(.opacity)
    }
}

private struct TypingIndicatorView: View {
    @State private var visibleDotCount: Int = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .frame(width: 6, height: 6)
                    .opacity(index < visibleDotCount ? 1.0 : 0.2)
            }
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                visibleDotCount = (visibleDotCount + 1) % 4
            }
        }
    }
}
