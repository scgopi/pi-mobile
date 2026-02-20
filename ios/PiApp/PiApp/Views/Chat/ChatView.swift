import SwiftUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Theme.paddingMedium) {
                        ForEach(viewModel.messages) { message in
                            if message.role == "user" {
                                UserBubble(content: message.content)
                            } else {
                                VStack(alignment: .leading, spacing: Theme.paddingSmall) {
                                    if let thinking = message.thinking, !thinking.isEmpty {
                                        ThinkingView(text: thinking)
                                    }

                                    if !message.content.isEmpty || message.isStreaming {
                                        AssistantBubble(
                                            content: message.content,
                                            isStreaming: message.isStreaming
                                        )
                                    }

                                    ForEach(message.toolCalls) { toolCall in
                                        ToolCallCard(toolCall: toolCall)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.paddingLarge)
                    .padding(.vertical, Theme.paddingMedium)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let lastMessage = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.streamingText) { _, _ in
                    if let lastMessage = viewModel.messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }

            // Error banner
            if let error = viewModel.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.error)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.error)
                    Spacer()
                    Button {
                        viewModel.error = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.horizontal, Theme.paddingLarge)
                .padding(.vertical, Theme.paddingMedium)
                .background(Theme.error.opacity(0.1))
            }

            Divider()

            // Input bar
            InputBar(
                text: $viewModel.inputText,
                isStreaming: viewModel.isStreaming,
                onSend: { viewModel.sendMessage() },
                onCancel: { viewModel.cancelStreaming() }
            )
        }
        .navigationTitle(viewModel.session?.title ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ThinkingView: View {
    let text: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.paddingSmall) {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "brain")
                        .foregroundStyle(Theme.thinkingText)
                    Text("Thinking")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.thinkingText)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(Theme.thinkingText)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(Theme.thinkingText)
                    .padding(Theme.paddingMedium)
            }
        }
        .padding(Theme.paddingMedium)
        .background(Theme.thinkingBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                .stroke(Theme.thinkingBorder, lineWidth: 1)
        )
    }
}
