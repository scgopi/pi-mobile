package com.pimobile.app.ui.chat

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.pimobile.app.PiMobileApp
import com.pimobile.app.ui.components.ModelPickerSheet
import com.pimobile.app.viewmodel.ChatMessage
import com.pimobile.app.viewmodel.ChatViewModel
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(
    sessionId: String,
    onBack: () -> Unit,
    viewModel: ChatViewModel = viewModel()
) {
    var showModelPicker by remember { mutableStateOf(false) }
    val uiState by viewModel.uiState.collectAsState()
    val listState = rememberLazyListState()
    val coroutineScope = rememberCoroutineScope()

    LaunchedEffect(sessionId) {
        viewModel.initSession(sessionId)
    }

    LaunchedEffect(uiState.messages.size) {
        if (uiState.messages.isNotEmpty()) {
            listState.animateScrollToItem(uiState.messages.size - 1)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text("Pi Mobile", fontWeight = FontWeight.SemiBold)
                        uiState.selectedModel?.let { model ->
                            Text(
                                text = model.name,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                            )
                        }
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            painter = painterResource(android.R.drawable.ic_menu_revert),
                            contentDescription = "Back"
                        )
                    }
                },
                actions = {
                    if (uiState.inputTokens > 0 || uiState.outputTokens > 0) {
                        Text(
                            text = "${uiState.inputTokens}/${uiState.outputTokens}",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
                            modifier = Modifier.padding(end = 8.dp)
                        )
                    }
                    TextButton(onClick = { showModelPicker = true }) {
                        Text("Model")
                    }
                }
            )
        },
        bottomBar = {
            InputBar(
                onSend = { text ->
                    viewModel.sendMessage(text)
                    coroutineScope.launch {
                        if (uiState.messages.isNotEmpty()) {
                            listState.animateScrollToItem(uiState.messages.size)
                        }
                    }
                },
                isStreaming = uiState.isStreaming,
                onCancel = { viewModel.cancelStreaming() }
            )
        }
    ) { paddingValues ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            if (uiState.messages.isEmpty() && !uiState.isStreaming) {
                EmptyState(modifier = Modifier.align(Alignment.Center))
            } else {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(vertical = 8.dp)
                ) {
                    items(uiState.messages) { message ->
                        when (message) {
                            is ChatMessage.User -> UserBubble(text = message.text)
                            is ChatMessage.Assistant -> AssistantBubble(
                                text = message.text,
                                thinking = message.thinking
                            )
                            is ChatMessage.ToolCallMsg -> ToolCallCard(
                                name = message.name,
                                input = message.input,
                                result = message.result
                            )
                            is ChatMessage.ErrorMsg -> ErrorBubble(message = message.message)
                        }
                    }

                    if (uiState.isStreaming && uiState.currentStreamText.isNotEmpty()) {
                        item {
                            AssistantBubble(
                                text = uiState.currentStreamText,
                                thinking = uiState.currentThinkingText.ifEmpty { null }
                            )
                        }
                    }

                    if (uiState.isStreaming && uiState.currentStreamText.isEmpty()) {
                        item {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(16.dp),
                                horizontalArrangement = Arrangement.Start
                            ) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(24.dp),
                                    strokeWidth = 2.dp
                                )
                                Spacer(modifier = Modifier.width(8.dp))
                                Text(
                                    "Thinking...",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    if (showModelPicker) {
        ModelPickerSheet(
            catalogue = PiMobileApp.instance.modelCatalogue,
            currentModel = uiState.selectedModel,
            onModelSelected = { model ->
                viewModel.setModel(model)
                showModelPicker = false
            },
            onDismiss = { showModelPicker = false }
        )
    }
}

@Composable
private fun EmptyState(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = "Pi Mobile",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.primary
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "AI assistant with tool capabilities",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
        )
        Spacer(modifier = Modifier.height(24.dp))
        Text(
            text = "Select a model and start chatting",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f)
        )
    }
}

@Composable
fun ErrorBubble(message: String, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.errorContainer
    ) {
        Text(
            text = message,
            modifier = Modifier.padding(12.dp),
            color = MaterialTheme.colorScheme.onErrorContainer,
            style = MaterialTheme.typography.bodyMedium
        )
    }
}
