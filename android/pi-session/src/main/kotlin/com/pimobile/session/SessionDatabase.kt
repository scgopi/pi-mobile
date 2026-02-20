package com.pimobile.session

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(
    entities = [SessionEntity::class, EntryEntity::class],
    version = 1,
    exportSchema = false
)
abstract class SessionDatabase : RoomDatabase() {

    abstract fun sessionDao(): SessionDao
    abstract fun entryDao(): EntryDao

    companion object {
        @Volatile
        private var INSTANCE: SessionDatabase? = null

        fun getInstance(context: Context): SessionDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    SessionDatabase::class.java,
                    "pi_sessions.db"
                )
                    .setJournalMode(JournalMode.WRITE_AHEAD_LOGGING)
                    .build()
                INSTANCE = instance
                instance
            }
        }
    }
}
