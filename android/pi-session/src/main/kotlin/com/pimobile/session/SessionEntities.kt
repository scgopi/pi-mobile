package com.pimobile.session

import androidx.room.*

@Entity(tableName = "sessions")
data class SessionEntity(
    @PrimaryKey val id: String,
    val title: String?,
    @ColumnInfo(name = "created_at") val createdAt: Long,
    @ColumnInfo(name = "updated_at") val updatedAt: Long,
    @ColumnInfo(name = "leaf_id") val leafId: String?,
    val metadata: String?
)

@Entity(
    tableName = "entries",
    foreignKeys = [
        ForeignKey(
            entity = SessionEntity::class,
            parentColumns = ["id"],
            childColumns = ["session_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index("session_id"),
        Index("parent_id"),
        Index("session_id", "timestamp")
    ]
)
data class EntryEntity(
    @PrimaryKey val id: String,
    @ColumnInfo(name = "session_id") val sessionId: String,
    @ColumnInfo(name = "parent_id") val parentId: String?,
    val type: String,
    val timestamp: Long,
    val data: String
)
