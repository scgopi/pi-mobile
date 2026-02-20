package com.pimobile.app

import android.app.Application
import com.pimobile.ai.LlmClient
import com.pimobile.ai.ModelCatalogue
import com.pimobile.agent.AgentLoop
import com.pimobile.extensions.ExtensionRegistry
import com.pimobile.session.SessionDatabase
import com.pimobile.session.SessionRepository

class PiMobileApp : Application() {

    lateinit var llmClient: LlmClient
        private set
    lateinit var modelCatalogue: ModelCatalogue
        private set
    lateinit var agentLoop: AgentLoop
        private set
    lateinit var sessionRepository: SessionRepository
        private set
    lateinit var extensionRegistry: ExtensionRegistry
        private set
    lateinit var sessionDatabase: SessionDatabase
        private set

    override fun onCreate() {
        super.onCreate()
        instance = this

        llmClient = LlmClient()
        modelCatalogue = ModelCatalogue()

        // Load model catalogue from bundled asset
        try {
            val json = assets.open("model-catalogue.json").bufferedReader().readText()
            modelCatalogue.loadFromJson(json)
        } catch (_: Exception) { }

        agentLoop = AgentLoop(llmClient)
        sessionDatabase = SessionDatabase.getInstance(this)
        sessionRepository = SessionRepository(sessionDatabase)
        extensionRegistry = ExtensionRegistry()
    }

    companion object {
        lateinit var instance: PiMobileApp
            private set
    }
}
