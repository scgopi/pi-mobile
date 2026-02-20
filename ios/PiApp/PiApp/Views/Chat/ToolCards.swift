import SwiftUI
import PiAgentCore

struct ToolCallCard: View {
    let toolCall: DisplayToolCall
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: toolCall.isComplete ? (toolCall.isError ? "xmark.circle.fill" : "checkmark.circle.fill") : "arrow.triangle.2.circlepath")
                        .foregroundStyle(toolCall.isComplete ? (toolCall.isError ? Theme.error : Theme.success) : Theme.info)

                    Text(toolCall.name)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.textPrimary)

                    Spacer()

                    if !toolCall.isComplete {
                        ProgressView()
                            .scaleEffect(0.7)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, Theme.paddingMedium)
                .padding(.vertical, Theme.paddingMedium)
                .background(Theme.toolHeaderBackground)
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                Divider()

                VStack(alignment: .leading, spacing: Theme.paddingMedium) {
                    if !toolCall.input.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.paddingSmall) {
                            Text("Input")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.textSecondary)
                            Text(toolCall.input)
                                .font(Theme.codeFontSmall)
                                .foregroundStyle(Theme.textPrimary)
                                .padding(Theme.paddingSmall)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.surfaceVariant)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                        }
                    }

                    if let output = toolCall.output {
                        VStack(alignment: .leading, spacing: Theme.paddingSmall) {
                            Text("Output")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.textSecondary)

                            if let details = toolCall.details {
                                ToolResultRenderer(details: details)
                            } else {
                                Text(output)
                                    .font(Theme.codeFontSmall)
                                    .foregroundStyle(toolCall.isError ? Theme.error : Theme.textPrimary)
                                    .padding(Theme.paddingSmall)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Theme.surfaceVariant)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                            }
                        }
                    }
                }
                .padding(Theme.paddingMedium)
            }
        }
        .background(Theme.toolBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                .stroke(Theme.toolBorder, lineWidth: 1)
        )
    }
}
