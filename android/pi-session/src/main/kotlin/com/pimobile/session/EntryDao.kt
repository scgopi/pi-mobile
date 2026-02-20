package com.pimobile.session

import androidx.room.*

@Dao
interface EntryDao {

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entry: EntryEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(entries: List<EntryEntity>)

    @Query("SELECT * FROM entries WHERE id = :entryId")
    suspend fun getById(entryId: String): EntryEntity?

    @Query("SELECT * FROM entries WHERE session_id = :sessionId ORDER BY timestamp ASC")
    suspend fun getBySessionId(sessionId: String): List<EntryEntity>

    @Query("SELECT * FROM entries WHERE parent_id = :parentId")
    suspend fun getChildren(parentId: String): List<EntryEntity>

    @Query("SELECT * FROM entries WHERE session_id = :sessionId AND parent_id IS NULL")
    suspend fun getRoots(sessionId: String): List<EntryEntity>

    @Query("""
        WITH RECURSIVE branch(id, session_id, parent_id, type, timestamp, data) AS (
            SELECT id, session_id, parent_id, type, timestamp, data
            FROM entries WHERE id = :leafId
            UNION ALL
            SELECT e.id, e.session_id, e.parent_id, e.type, e.timestamp, e.data
            FROM entries e
            INNER JOIN branch b ON e.id = b.parent_id
        )
        SELECT * FROM branch ORDER BY timestamp ASC
    """)
    suspend fun getBranch(leafId: String): List<EntryEntity>

    @Query("""
        SELECT e.* FROM entries e
        WHERE e.session_id = :sessionId
        AND e.id NOT IN (SELECT DISTINCT parent_id FROM entries WHERE parent_id IS NOT NULL AND session_id = :sessionId)
    """)
    suspend fun getLeafEntries(sessionId: String): List<EntryEntity>

    @Query("DELETE FROM entries WHERE id = :entryId")
    suspend fun deleteById(entryId: String)

    @Query("DELETE FROM entries WHERE session_id = :sessionId")
    suspend fun deleteBySessionId(sessionId: String)
}
