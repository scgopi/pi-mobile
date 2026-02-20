import Foundation
import SwiftUI
import PiSession
import PiAI

@MainActor
@Observable
public final class SessionListViewModel {
    public var sessions: [Session] = []
    public var error: String?

    private let agentRepository: AgentRepository

    public init(agentRepository: AgentRepository) {
        self.agentRepository = agentRepository
    }

    public func loadSessions() {
        do {
            sessions = try agentRepository.listSessions()
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func createSession(title: String, provider: String, modelId: String, systemPrompt: String = "") -> Session? {
        do {
            let session = try agentRepository.createSession(
                title: title,
                provider: provider,
                modelId: modelId,
                systemPrompt: systemPrompt
            )
            loadSessions()
            return session
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    public func deleteSession(_ session: Session) {
        do {
            try agentRepository.deleteSession(id: session.id)
            loadSessions()
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func deleteSession(at offsets: IndexSet) {
        for index in offsets {
            let session = sessions[index]
            deleteSession(session)
        }
    }
}
