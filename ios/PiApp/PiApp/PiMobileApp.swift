import SwiftUI
import PiAI
import PiSession

@main
struct PiMobileApp: App {
    private let sessionDatabase: SessionDatabase
    private let modelCatalogue: ModelCatalogue
    private let apiKeyRepository: ApiKeyRepository
    private let agentRepository: AgentRepository

    init() {
        // Initialize database
        let dbPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("pi-sessions.db").path

        do {
            sessionDatabase = try SessionDatabase(path: dbPath)
        } catch {
            fatalError("Failed to initialize session database: \(error)")
        }

        // Load model catalogue
        modelCatalogue = ModelCatalogue()
        modelCatalogue.loadFromBundle()

        // API key storage
        apiKeyRepository = ApiKeyRepository()

        // Agent repository
        agentRepository = AgentRepository(
            sessionDatabase: sessionDatabase,
            modelCatalogue: modelCatalogue,
            apiKeyRepository: apiKeyRepository
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                agentRepository: agentRepository,
                apiKeyRepository: apiKeyRepository,
                modelCatalogue: modelCatalogue
            )
        }
    }
}
