//
//  HeaderView.swift
//  aide-de-camp
//
//  Created by Alexander Eckhart on 30.08.25.
//

import SwiftUI

struct HeaderView: View {
    let onNewSession: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack {
            Text("Aide-de-camp")
                .font(.headline)
                .padding(.leading)

            Spacer()

            Button(action: onNewSession) {
                Image(systemName: "plus.bubble")
                    .font(.system(size: 18, weight: .medium))
            }
            .padding(.trailing, 8)
            .buttonStyle(.plain)

            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
            }
            .padding(.trailing)
            .buttonStyle(.plain)
        }
        .padding(.vertical, 16)
        .background(Color(UIColor.systemBackground))
    }
}
