import SwiftUI

struct InputBar: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.paddingMedium) {
            // Attach button placeholder
            Button {
                // Placeholder for future attachment support
            } label: {
                Image(systemName: "paperclip")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.bottom, 6)

            // Text input
            TextField("Message...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($isFocused)
                .onSubmit {
                    if !isStreaming {
                        onSend()
                    }
                }

            // Send / Cancel button
            if isStreaming {
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.error)
                }
                .padding(.bottom, 4)
            } else {
                Button {
                    onSend()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Theme.textTertiary : Theme.primaryVariant)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, Theme.paddingLarge)
        .padding(.vertical, Theme.paddingMedium)
        .background(Theme.background)
    }
}
