package com.pimobile.app.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.pimobile.ai.ModelCatalogue
import com.pimobile.ai.ModelDefinition

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ModelPickerSheet(
    catalogue: ModelCatalogue,
    currentModel: ModelDefinition?,
    onModelSelected: (ModelDefinition) -> Unit,
    onDismiss: () -> Unit
) {
    var searchQuery by remember { mutableStateOf("") }
    var selectedProvider by remember { mutableStateOf<String?>(null) }

    val allModels = remember { catalogue.allModels() }
    val providers = remember { catalogue.allProviders() }

    val filteredModels = allModels.filter { model ->
        val matchesProvider = selectedProvider == null || model.provider == selectedProvider
        val matchesSearch = searchQuery.isBlank() ||
                model.name.contains(searchQuery, ignoreCase = true) ||
                model.id.contains(searchQuery, ignoreCase = true) ||
                model.provider.contains(searchQuery, ignoreCase = true)
        matchesProvider && matchesSearch
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(bottom = 32.dp)
        ) {
            Text(
                text = "Select Model",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(bottom = 16.dp)
            )

            OutlinedTextField(
                value = searchQuery,
                onValueChange = { searchQuery = it },
                placeholder = { Text("Search models...") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                shape = RoundedCornerShape(12.dp)
            )

            Spacer(modifier = Modifier.height(12.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                FilterChip(
                    selected = selectedProvider == null,
                    onClick = { selectedProvider = null },
                    label = { Text("All") }
                )
                for (provider in providers) {
                    FilterChip(
                        selected = selectedProvider == provider,
                        onClick = {
                            selectedProvider = if (selectedProvider == provider) null else provider
                        },
                        label = { Text(provider) }
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            LazyColumn(
                modifier = Modifier.heightIn(max = 400.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                items(filteredModels) { model ->
                    ModelItem(
                        model = model,
                        isSelected = model.id == currentModel?.id && model.provider == currentModel.provider,
                        onClick = { onModelSelected(model) }
                    )
                }

                if (filteredModels.isEmpty()) {
                    item {
                        Text(
                            text = "No models found",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
                            modifier = Modifier.padding(16.dp)
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ModelItem(
    model: ModelDefinition,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(12.dp),
        color = if (isSelected) {
            MaterialTheme.colorScheme.primaryContainer
        } else {
            MaterialTheme.colorScheme.surface
        },
        tonalElevation = if (isSelected) 3.dp else 0.dp
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = model.name,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal
                )
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.padding(top = 2.dp)
                ) {
                    Text(
                        text = model.provider,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary
                    )
                    Text(
                        text = "${model.contextWindow / 1000}K ctx",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                    )
                }
            }

            Column(horizontalAlignment = Alignment.End) {
                val capabilities = buildList {
                    if (model.capabilities.vision) add("Vision")
                    if (model.capabilities.toolUse) add("Tools")
                    if (model.capabilities.reasoning) add("Think")
                }
                if (capabilities.isNotEmpty()) {
                    Text(
                        text = capabilities.joinToString(" "),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f)
                    )
                }
                Text(
                    text = "$${model.inputCostPer1M}/$${model.outputCostPer1M}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f)
                )
            }
        }
    }
}
