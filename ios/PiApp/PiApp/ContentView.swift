import SwiftUI
import PiAI
import PiSession

struct ContentView: View {
    @State var agentRepository: AgentRepository
    @State private var sessionListViewModel: SessionListViewModel
    @State private var chatViewModel: ChatViewModel
    @State private var selectedSession: Session?
    @State private var showSettings = false
    @State private var showNewSession = false

    let apiKeyRepository: ApiKeyRepository
    let modelCatalogue: ModelCatalogue

    init(agentRepository: AgentRepository, apiKeyRepository: ApiKeyRepository, modelCatalogue: ModelCatalogue) {
        self.agentRepository = agentRepository
        self.apiKeyRepository = apiKeyRepository
        self.modelCatalogue = modelCatalogue
        self._sessionListViewModel = State(initialValue: SessionListViewModel(agentRepository: agentRepository))
        self._chatViewModel = State(initialValue: ChatViewModel(agentRepository: agentRepository))
    }

    var body: some View {
        NavigationStack {
            SessionListView(
                viewModel: sessionListViewModel,
                onSelectSession: { session in
                    selectedSession = session
                    chatViewModel.loadSession(session)
                },
                onNewSession: {
                    showNewSession = true
                }
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .navigationDestination(item: $selectedSession) { _ in
                ChatView(viewModel: chatViewModel)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(apiKeyRepository: apiKeyRepository, modelCatalogue: modelCatalogue)
        }
        .sheet(isPresented: $showNewSession) {
            NewSessionSheet(
                modelCatalogue: modelCatalogue,
                onCreate: { title, provider, modelId, systemPrompt in
                    if let session = sessionListViewModel.createSession(
                        title: title,
                        provider: provider,
                        modelId: modelId,
                        systemPrompt: systemPrompt
                    ) {
                        selectedSession = session
                        chatViewModel.loadSession(session)
                    }
                    showNewSession = false
                }
            )
        }
    }
}

struct NewSessionSheet: View {
    let modelCatalogue: ModelCatalogue
    let onCreate: (String, String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var selectedProvider = ""
    @State private var selectedModelId = ""
    @State private var systemPrompt = ""
    @State private var showModelPicker = false

    var selectedModelName: String {
        if let model = modelCatalogue.get(provider: selectedProvider, id: selectedModelId) {
            return model.name
        }
        return "Select a model"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Conversation") {
                    TextField("Title", text: $title)
                }

                Section("Model") {
                    Button {
                        showModelPicker = true
                    } label: {
                        HStack {
                            Text("Model")
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(selectedModelName)
                                .foregroundStyle(selectedProvider.isEmpty ? Theme.textTertiary : Theme.primaryVariant)
                        }
                    }
                }

                Section("System Prompt (Optional)") {
                    TextEditor(text: $systemPrompt)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("New Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let sessionTitle = title.isEmpty ? selectedModelName : title
                        onCreate(sessionTitle, selectedProvider, selectedModelId, systemPrompt)
                    }
                    .disabled(selectedProvider.isEmpty || selectedModelId.isEmpty)
                }
            }
            .sheet(isPresented: $showModelPicker) {
                ModelPickerView(
                    modelCatalogue: modelCatalogue,
                    selectedProvider: $selectedProvider,
                    selectedModelId: $selectedModelId
                )
            }
        }
    }
}
