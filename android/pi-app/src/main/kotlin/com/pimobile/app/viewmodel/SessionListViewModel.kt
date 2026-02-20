package com.pimobile.app.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.pimobile.app.PiMobileApp
import com.pimobile.session.SessionEntity
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

data class SessionListUiState(
    val sessions: List<SessionEntity> = emptyList(),
    val isLoading: Boolean = true
)

class SessionListViewModel(application: Application) : AndroidViewModel(application) {

    private val app = application as PiMobileApp
    private val sessionRepository = app.sessionRepository

    private val _uiState = MutableStateFlow(SessionListUiState())
    val uiState: StateFlow<SessionListUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            sessionRepository.listSessions().collect { sessions ->
                _uiState.update { it.copy(sessions = sessions, isLoading = false) }
            }
        }
    }

    fun deleteSession(sessionId: String) {
        viewModelScope.launch {
            sessionRepository.deleteSession(sessionId)
        }
    }

    fun renameSession(sessionId: String, newTitle: String) {
        viewModelScope.launch {
            sessionRepository.updateSessionTitle(sessionId, newTitle)
        }
    }
}
