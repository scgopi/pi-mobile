package com.pimobile.session

import kotlinx.coroutines.flow.Flow
import java.util.UUID

class SessionRepository(private val database: SessionDatabase) {

    private val sessionDao = database.sessionDao()
    private val entryDao = database.entryDao()

    suspend fun createSession(title: String? = null, metadata: String? = null): SessionEntity {
        val now = System.currentTimeMillis()
        val session = SessionEntity(
            id = UUID.randomUUID().toString(),
            title = title,
            createdAt = now,
            updatedAt = now,
            leafId = null,
            metadata = metadata
        )
        sessionDao.insert(session)
        return session
    }

    suspend fun addEntry(
        sessionId: String,
        parentId: String?,
        type: String,
        data: String
    ): EntryEntity {
        val entry = EntryEntity(
            id = UUID.randomUUID().toString(),
            sessionId = sessionId,
            parentId = parentId,
            type = type,
            timestamp = System.currentTimeMillis(),
            data = data
        )
        entryDao.insert(entry)
        sessionDao.updateLeaf(sessionId, entry.id, entry.timestamp)
        return entry
    }

    suspend fun getBranch(leafId: String): List<EntryEntity> {
        return entryDao.getBranch(leafId)
    }

    suspend fun listBranches(sessionId: String): List<EntryEntity> {
        return entryDao.getLeafEntries(sessionId)
    }

    suspend fun switchBranch(sessionId: String, leafId: String) {
        sessionDao.updateLeaf(sessionId, leafId, System.currentTimeMillis())
    }

    fun listSessions(): Flow<List<SessionEntity>> {
        return sessionDao.getAllSessions()
    }

    suspend fun listSessionsList(): List<SessionEntity> {
        return sessionDao.getAllSessionsList()
    }

    suspend fun getSession(sessionId: String): SessionEntity? {
        return sessionDao.getById(sessionId)
    }

    suspend fun updateSessionTitle(sessionId: String, title: String) {
        sessionDao.updateTitle(sessionId, title, System.currentTimeMillis())
    }

    suspend fun deleteSession(sessionId: String) {
        entryDao.deleteBySessionId(sessionId)
        sessionDao.deleteById(sessionId)
    }

    suspend fun getEntry(entryId: String): EntryEntity? {
        return entryDao.getById(entryId)
    }

    suspend fun getSessionEntries(sessionId: String): List<EntryEntity> {
        return entryDao.getBySessionId(sessionId)
    }
}
