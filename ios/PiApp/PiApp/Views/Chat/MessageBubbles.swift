import SwiftUI

struct UserBubble: View {
    let content: String

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            Text(content)
                .foregroundStyle(Theme.userBubbleText)
                .padding(.horizontal, Theme.paddingLarge)
                .padding(.vertical, Theme.paddingMedium + 2)
                .background(Theme.userBubble)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
    }
}

struct AssistantBubble: View {
    let content: String
    var isStreaming: Bool = false

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                if content.isEmpty && isStreaming {
                    StreamingText(text: "")
                } else {
                    Text(LocalizedStringKey(content))
                        .foregroundStyle(Theme.assistantBubbleText)
                    if isStreaming {
                        BlinkingCursor()
                    }
                }
            }
            .padding(.horizontal, Theme.paddingLarge)
            .padding(.vertical, Theme.paddingMedium + 2)
            .background(Theme.assistantBubble)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            Spacer(minLength: 60)
        }
    }
}

struct BlinkingCursor: View {
    @State private var isVisible = true

    var body: some View {
        Text("|")
            .fontWeight(.bold)
            .foregroundStyle(Theme.primaryVariant)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    isVisible = false
                }
            }
    }
}
