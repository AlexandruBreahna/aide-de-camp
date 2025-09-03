//
//  Message.swift
//  aide-de-camp
//
//  Created by Alexander Eckhart on 30.08.25.
//

import Foundation

/// Represents a single chat message in the conversation.
struct Message: Identifiable, Equatable {
    enum Sender {
        case user
        case ai
    }

    let id: UUID
    let sender: Sender
    let text: String
    let timestamp: Date

    init(id: UUID = UUID(), sender: Sender, text: String, timestamp: Date = Date()) {
        self.id = id
        self.sender = sender
        self.text = text
        self.timestamp = timestamp
    }

    /// For display use (chat bubble alignment, color, etc.)
    var isFromUser: Bool {
        sender == .user
    }
}
