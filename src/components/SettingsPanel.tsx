import React, { useCallback, useState } from 'react';
import {
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import type { AgentRuntime } from '../agent-runtime/agent-runtime';
import { BUILT_IN_MODELS } from '../agent-runtime/types';
import type { Model } from '../agent-runtime/types';

interface Props {
  runtime: AgentRuntime;
  onSave?: () => void;
}

export function SettingsPanel({ runtime, onSave }: Props): React.ReactElement {
  const [apiKey, setApiKey] = useState(runtime.apiKey);
  const [systemPrompt, setSystemPrompt] = useState(runtime.systemPrompt);
  const [selectedModel, setSelectedModel] = useState<Model>(runtime.model);

  const handleSave = useCallback(() => {
    runtime.setApiKey(apiKey.trim());
    runtime.setSystemPrompt(systemPrompt.trim());
    runtime.setModel(selectedModel);
    onSave?.();
  }, [apiKey, systemPrompt, selectedModel, runtime, onSave]);

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
      <ScrollView contentContainerStyle={styles.scrollContent} keyboardShouldPersistTaps="handled">
        <Text style={styles.sectionTitle}>Model</Text>
        <View style={styles.modelList}>
          {BUILT_IN_MODELS.map((model) => (
            <TouchableOpacity
              key={`${model.provider}-${model.id}`}
              style={[
                styles.modelItem,
                selectedModel.id === model.id && selectedModel.provider === model.provider
                  ? styles.modelItemSelected
                  : null,
              ]}
              onPress={() => setSelectedModel(model)}
            >
              <Text
                style={[
                  styles.modelName,
                  selectedModel.id === model.id && selectedModel.provider === model.provider
                    ? styles.modelNameSelected
                    : null,
                ]}
              >
                {model.name}
              </Text>
              <Text style={styles.modelProvider}>{model.provider}</Text>
            </TouchableOpacity>
          ))}
        </View>

        <Text style={styles.sectionTitle}>API Key</Text>
        <Text style={styles.hint}>
          Required for the selected provider.  Keys are stored only in memory and cleared when the
          app restarts.
        </Text>
        <TextInput
          style={styles.input}
          value={apiKey}
          onChangeText={setApiKey}
          placeholder="sk-… / sk-ant-… / AIza…"
          placeholderTextColor="#94a3b8"
          autoCapitalize="none"
          autoCorrect={false}
          secureTextEntry
        />

        <Text style={styles.sectionTitle}>System Prompt</Text>
        <TextInput
          style={[styles.input, styles.multilineInput]}
          value={systemPrompt}
          onChangeText={setSystemPrompt}
          placeholder="You are a helpful assistant."
          placeholderTextColor="#94a3b8"
          multiline
          numberOfLines={4}
          textAlignVertical="top"
        />

        <TouchableOpacity style={styles.saveButton} onPress={handleSave}>
          <Text style={styles.saveButtonText}>Save</Text>
        </TouchableOpacity>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#ffffff',
  },
  scrollContent: {
    padding: 20,
    paddingBottom: 40,
  },
  sectionTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: '#64748b',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
    marginTop: 24,
    marginBottom: 8,
  },
  hint: {
    fontSize: 13,
    color: '#94a3b8',
    marginBottom: 8,
    lineHeight: 18,
  },
  modelList: {
    gap: 8,
  },
  modelItem: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 14,
    paddingVertical: 12,
    borderRadius: 12,
    borderWidth: 1.5,
    borderColor: '#e2e8f0',
    backgroundColor: '#f8fafc',
  },
  modelItemSelected: {
    borderColor: '#6366f1',
    backgroundColor: '#eef2ff',
  },
  modelName: {
    fontSize: 15,
    fontWeight: '500',
    color: '#334155',
  },
  modelNameSelected: {
    color: '#4f46e5',
  },
  modelProvider: {
    fontSize: 12,
    color: '#94a3b8',
    textTransform: 'capitalize',
  },
  input: {
    backgroundColor: '#f8fafc',
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#e2e8f0',
    paddingHorizontal: 14,
    paddingVertical: 12,
    fontSize: 15,
    color: '#1e293b',
  },
  multilineInput: {
    height: 100,
  },
  saveButton: {
    marginTop: 32,
    backgroundColor: '#6366f1',
    borderRadius: 14,
    paddingVertical: 14,
    alignItems: 'center',
  },
  saveButtonText: {
    color: '#ffffff',
    fontSize: 16,
    fontWeight: '600',
  },
});
