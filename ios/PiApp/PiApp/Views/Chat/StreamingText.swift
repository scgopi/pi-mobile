import SwiftUI

struct StreamingText: View {
    let text: String
    @State private var cursorVisible = true

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if text.isEmpty {
                HStack(spacing: 4) {
                    ForEach(0..<3) { index in
                        TypingDot(delay: Double(index) * 0.2)
                    }
                }
            } else {
                Text(text)
                    .foregroundStyle(Theme.assistantBubbleText)
                Text("|")
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.primaryVariant)
                    .opacity(cursorVisible ? 1 : 0)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                            cursorVisible = false
                        }
                    }
            }
        }
    }
}

struct TypingDot: View {
    let delay: Double
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(Theme.textSecondary)
            .frame(width: 6, height: 6)
            .offset(y: isAnimating ? -4 : 0)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.4)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    isAnimating = true
                }
            }
    }
}
