import SwiftUI
import PiSession

struct SessionListView: View {
    @Bindable var viewModel: SessionListViewModel
    let onSelectSession: (Session) -> Void
    let onNewSession: () -> Void

    var body: some View {
        List {
            if viewModel.sessions.isEmpty {
                ContentUnavailableView(
                    "No Conversations",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Start a new conversation to get going.")
                )
            } else {
                ForEach(viewModel.sessions) { session in
                    Button {
                        onSelectSession(session)
                    } label: {
                        SessionRow(session: session)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    viewModel.deleteSession(at: offsets)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Conversations")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onNewSession()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear {
            viewModel.loadSessions()
        }
    }
}

struct SessionRow: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.paddingSmall) {
            Text(session.title)
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            HStack {
                Text(session.modelProvider)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)

                Text("/")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)

                Text(session.modelId)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)

                Spacer()

                Text(session.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.vertical, Theme.paddingSmall)
    }
}
