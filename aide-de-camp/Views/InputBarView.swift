//
//  InputBarView.swift
//  aide-de-camp
//
//  Created by Alexander Eckhart on 30.08.25.
//

import SwiftUI

struct InputBarView: View {
    @Binding var text: String
    let isLoading: Bool
    let onSend: () -> Void

    // Autofocus support (bound from ChatView)
    @FocusState.Binding var isInputFocused: Bool

    @State private var measuredHeight: CGFloat = 0

    private let font: Font = .system(size: 16)
    private let uiFont = UIFont.systemFont(ofSize: 16)
    private let maxRows = 6
    private let sendButtonSize: CGFloat = 32
    private let verticalPadding: CGFloat = 12
    private let lineHeight: CGFloat = 24

    var body: some View {
        let minHeight = lineHeight + (verticalPadding * 2)
        let maxHeight = (lineHeight * CGFloat(maxRows)) + (verticalPadding * 2)
        let currentHeight = clampHeight(minHeight: minHeight, maxHeight: maxHeight)
        let contentHeight = min(measuredHeight, currentHeight)
        let cornerRadius: CGFloat = 28 // Fixed CSS-like radius

        HStack {
            // Wrapper with gray background containing both input and button
            ZStack(alignment: .trailing) {
                // Outer gray pill background
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(UIColor.systemGray6))
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color(UIColor.systemGray4), lineWidth: 1))

                HStack(alignment: .center, spacing: 8) {
                    // Text input area (transparent background)
                    ZStack(alignment: .leading) {
                        HStack { // wrapper to allow vertical centering via padding
                            ZStack(alignment: .leading) {
                                TextEditor(text: $text)
                                    .font(font)
                                    .focused($isInputFocused)
                                    .scrollDisabled(measuredHeight <= currentHeight)
                                    .scrollContentBackground(.hidden)
                                    .background(Color.clear)
                                    .frame(height: contentHeight)
                                    .lineSpacing(lineHeight - uiFont.lineHeight)
                                    .padding(.leading, 4)
                                    .padding(.trailing, 4)
                                    .background(
                                        HiddenMeasureText(
                                            text: text,
                                            uiFont: uiFont,
                                            lineHeight: lineHeight,
                                            horizontalPadding: 32,
                                            verticalPadding: verticalPadding * 2
                                        )
                                        .onPreferenceChange(ViewHeightKey.self) { h in
                                            measuredHeight = h
                                        }
                                    )
                            }
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                        }
                        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Type a message...")
                                .font(font)
                                .foregroundColor(.secondary)
                                .frame(height: contentHeight)
                                .padding(.leading, 8)
                                .padding(.trailing, 8)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    Button(action: {
                        guard !isLoading else { return }
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSend()
                        // keep focus after sending so keyboard stays up
                        DispatchQueue.main.async { isInputFocused = true }
                    }) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: sendButtonSize, height: sendButtonSize)
                            .background(Circle().fill(Color.black))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity((isLoading || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 0.4 : 1.0)
                }
                .padding(.horizontal, 8)
            }
            .frame(height: currentHeight)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(UIColor.systemBackground))
    }

    private func clampHeight(minHeight: CGFloat, maxHeight: CGFloat) -> CGFloat {
        min(max(measuredHeight, minHeight), maxHeight)
    }
}

// MARK: - Hidden text measurer

private struct ViewHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct HiddenMeasureText: View {
    let text: String
    let uiFont: UIFont
    let lineHeight: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width - horizontalPadding, 0)
            Text(text.isEmpty ? " " : text + " ")
                .font(Font(uiFont))
                .lineSpacing(lineHeight - uiFont.lineHeight) // Ensure consistent line height
                .frame(width: width, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .opacity(0)
                .background(
                    GeometryReader { inner in
                        Color.clear.preference(
                            key: ViewHeightKey.self,
                            value: inner.size.height + verticalPadding
                        )
                    }
                )
        }
        .allowsHitTesting(false)
    }
}
