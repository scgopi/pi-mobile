import SwiftUI
import PiAgentCore

struct ToolResultRenderer: View {
    let details: ToolResultDetails

    var body: some View {
        switch details {
        case .file(let path, let content, let language):
            FileViewer(path: path, content: content, language: language)
        case .diff(let path, let hunks):
            DiffViewer(path: path, hunks: hunks)
        case .table(let columns, let rows):
            TableViewer(columns: columns, rows: rows)
        case .error(let message, let code):
            ErrorCard(message: message, code: code)
        }
    }
}

// MARK: - File Viewer

struct FileViewer: View {
    let path: String
    let content: String
    let language: String?
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "doc.text")
                    .font(.caption)
                Text(path)
                    .font(.caption)
                    .fontWeight(.medium)
                if let language = language {
                    Text(language)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Theme.primaryVariant.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Spacer()
                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }
            .padding(Theme.paddingMedium)
            .foregroundStyle(Theme.textSecondary)
            .background(Theme.toolHeaderBackground)

            if isExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(content)
                        .font(Theme.codeFontSmall)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(Theme.paddingMedium)
                }
                .frame(maxHeight: 300)
            }
        }
        .background(Theme.surfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
    }
}

// MARK: - Diff Viewer

struct DiffViewer: View {
    let path: String
    let hunks: [DiffHunk]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption)
                Text(path)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
            }
            .padding(Theme.paddingMedium)
            .foregroundStyle(Theme.textSecondary)
            .background(Theme.toolHeaderBackground)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(hunks.enumerated()), id: \.offset) { _, hunk in
                    Text("@@ -\(hunk.startLineOld),\(hunk.countOld) +\(hunk.startLineNew),\(hunk.countNew) @@")
                        .font(Theme.codeFontSmall)
                        .foregroundStyle(Theme.info)
                        .padding(.horizontal, Theme.paddingMedium)
                        .padding(.vertical, 2)

                    ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                        HStack(spacing: 0) {
                            Text(linePrefix(line.type))
                                .font(Theme.codeFontSmall)
                                .frame(width: 16)
                            Text(line.content)
                                .font(Theme.codeFontSmall)
                        }
                        .foregroundStyle(lineColor(line.type))
                        .padding(.horizontal, Theme.paddingMedium)
                        .padding(.vertical, 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(lineBackground(line.type))
                    }
                }
            }
        }
        .background(Theme.surfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
    }

    private func linePrefix(_ type: DiffLineType) -> String {
        switch type {
        case .add: return "+"
        case .remove: return "-"
        case .context: return " "
        }
    }

    private func lineColor(_ type: DiffLineType) -> Color {
        switch type {
        case .add: return Theme.diffAddText
        case .remove: return Theme.diffRemoveText
        case .context: return Theme.textPrimary
        }
    }

    private func lineBackground(_ type: DiffLineType) -> Color {
        switch type {
        case .add: return Theme.diffAdd
        case .remove: return Theme.diffRemove
        case .context: return Color.clear
        }
    }
}

// MARK: - Table Viewer

struct TableViewer: View {
    let columns: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        Text(column)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, Theme.paddingMedium)
                            .padding(.vertical, Theme.paddingSmall)
                            .frame(minWidth: 80, alignment: .leading)
                    }
                }
                .background(Theme.toolHeaderBackground)

                Divider()

                // Rows
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell)
                                .font(Theme.codeFontSmall)
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, Theme.paddingMedium)
                                .padding(.vertical, Theme.paddingSmall)
                                .frame(minWidth: 80, alignment: .leading)
                        }
                    }
                    .background(rowIndex % 2 == 0 ? Color.clear : Theme.surfaceVariant.opacity(0.5))
                }
            }
        }
        .background(Theme.surfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
    }
}

// MARK: - Error Card

struct ErrorCard: View {
    let message: String
    let code: String?

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.error)
            VStack(alignment: .leading, spacing: 2) {
                if let code = code {
                    Text(code)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.error)
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
        }
        .padding(Theme.paddingMedium)
        .background(Theme.error.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                .stroke(Theme.error.opacity(0.3), lineWidth: 1)
        )
    }
}
