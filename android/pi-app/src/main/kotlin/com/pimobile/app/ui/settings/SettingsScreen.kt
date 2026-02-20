package com.pimobile.app.ui.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import com.pimobile.app.repository.ApiKeyRepository

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onBack: () -> Unit
) {
    val context = LocalContext.current
    val apiKeyRepository = remember { ApiKeyRepository(context) }

    val providers = listOf(
        "openai" to "OpenAI",
        "anthropic" to "Anthropic",
        "azure" to "Azure OpenAI",
        "google" to "Google AI",
        "groq" to "Groq",
        "cerebras" to "Cerebras",
        "mistral" to "Mistral"
    )

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings", fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            painter = painterResource(android.R.drawable.ic_menu_revert),
                            contentDescription = "Back"
                        )
                    }
                }
            )
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .verticalScroll(rememberScrollState())
                .padding(16.dp)
        ) {
            Text(
                text = "API Keys",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(bottom = 16.dp)
            )

            for ((providerId, providerName) in providers) {
                ApiKeyField(
                    providerName = providerName,
                    providerId = providerId,
                    apiKeyRepository = apiKeyRepository
                )
                Spacer(modifier = Modifier.height(12.dp))
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 16.dp))

            Text(
                text = "Azure Endpoint",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(bottom = 8.dp)
            )

            AzureEndpointField(apiKeyRepository = apiKeyRepository)

            Spacer(modifier = Modifier.height(4.dp))

            Text(
                text = "Full Azure OpenAI resource URL, e.g.\nhttps://myresource.cognitiveservices.azure.com/openai/responses?api-version=2025-04-01-preview",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f)
            )

            HorizontalDivider(modifier = Modifier.padding(vertical = 16.dp))

            Text(
                text = "About",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(bottom = 8.dp)
            )
            Text(
                text = "Pi Mobile v1.0",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
            )
            Text(
                text = "Multi-provider AI assistant with tool capabilities",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f),
                modifier = Modifier.padding(top = 4.dp)
            )
        }
    }
}

@Composable
private fun ApiKeyField(
    providerName: String,
    providerId: String,
    apiKeyRepository: ApiKeyRepository
) {
    var apiKey by remember { mutableStateOf(apiKeyRepository.getApiKey(providerId) ?: "") }
    var showKey by remember { mutableStateOf(false) }
    var saved by remember { mutableStateOf(apiKeyRepository.hasApiKey(providerId)) }

    OutlinedTextField(
        value = apiKey,
        onValueChange = { newValue ->
            apiKey = newValue
            saved = false
        },
        label = { Text(providerName) },
        placeholder = { Text("Enter API key...") },
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
        visualTransformation = if (showKey) VisualTransformation.None else PasswordVisualTransformation(),
        trailingIcon = {
            Row {
                IconButton(onClick = { showKey = !showKey }) {
                    Icon(
                        painter = painterResource(
                            if (showKey) android.R.drawable.ic_menu_view else android.R.drawable.ic_secure
                        ),
                        contentDescription = if (showKey) "Hide" else "Show"
                    )
                }
                if (apiKey.isNotEmpty() && !saved) {
                    IconButton(onClick = {
                        apiKeyRepository.setApiKey(providerId, apiKey)
                        saved = true
                    }) {
                        Icon(
                            painter = painterResource(android.R.drawable.ic_menu_save),
                            contentDescription = "Save",
                            tint = MaterialTheme.colorScheme.primary
                        )
                    }
                }
                if (saved && apiKey.isNotEmpty()) {
                    IconButton(onClick = {
                        apiKeyRepository.removeApiKey(providerId)
                        apiKey = ""
                        saved = false
                    }) {
                        Icon(
                            painter = painterResource(android.R.drawable.ic_menu_delete),
                            contentDescription = "Remove",
                            tint = MaterialTheme.colorScheme.error
                        )
                    }
                }
            }
        },
        supportingText = {
            if (saved) {
                Text("Saved", color = MaterialTheme.colorScheme.primary)
            }
        }
    )
}

@Composable
private fun AzureEndpointField(apiKeyRepository: ApiKeyRepository) {
    var endpoint by remember { mutableStateOf(apiKeyRepository.getSetting("azure", "endpoint") ?: "") }
    var saved by remember { mutableStateOf(endpoint.isNotEmpty()) }

    OutlinedTextField(
        value = endpoint,
        onValueChange = { newValue ->
            endpoint = newValue
            saved = false
        },
        label = { Text("Endpoint URL") },
        placeholder = { Text("https://...cognitiveservices.azure.com/...") },
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
        trailingIcon = {
            if (endpoint.isNotEmpty() && !saved) {
                IconButton(onClick = {
                    apiKeyRepository.setSetting("azure", "endpoint", endpoint)
                    saved = true
                }) {
                    Icon(
                        painter = painterResource(android.R.drawable.ic_menu_save),
                        contentDescription = "Save",
                        tint = MaterialTheme.colorScheme.primary
                    )
                }
            }
        },
        supportingText = {
            if (saved) {
                Text("Saved", color = MaterialTheme.colorScheme.primary)
            }
        }
    )
}
