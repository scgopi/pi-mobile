import { StatusBar } from 'expo-status-bar';
import React, { useRef, useState } from 'react';
import {
  Modal,
  Platform,
  SafeAreaView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { AgentRuntime } from './src/agent-runtime';
import { BUILT_IN_MODELS } from './src/agent-runtime/types';
import { ChatView } from './src/components/ChatView';
import { SettingsPanel } from './src/components/SettingsPanel';

export default function App(): React.ReactElement {
  const runtimeRef = useRef<AgentRuntime>(
    new AgentRuntime({
      model: BUILT_IN_MODELS[0],
      apiKey: '',
      systemPrompt: 'You are a helpful assistant.',
    })
  );

  const [settingsVisible, setSettingsVisible] = useState(false);
  const [modelName, setModelName] = useState(BUILT_IN_MODELS[0].name);

  const handleSettingsSave = (): void => {
    setModelName(runtimeRef.current.model.name);
    setSettingsVisible(false);
    // Clear conversation when model/key changes
    runtimeRef.current.clearMessages();
  };

  return (
    <SafeAreaView style={styles.safeArea}>
      <StatusBar style="auto" />

      {/* Header */}
      <View style={styles.header}>
        <View style={styles.headerLeft} />
        <View style={styles.headerCenter}>
          <Text style={styles.headerTitle}>pi-mobile</Text>
          <Text style={styles.headerSubtitle}>{modelName}</Text>
        </View>
        <TouchableOpacity
          style={styles.settingsButton}
          onPress={() => setSettingsVisible(true)}
          hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}
        >
          <Text style={styles.settingsIcon}>⚙️</Text>
        </TouchableOpacity>
      </View>

      {/* Chat */}
      <ChatView runtime={runtimeRef.current} />

      {/* Settings modal */}
      <Modal
        visible={settingsVisible}
        animationType="slide"
        presentationStyle={Platform.OS === 'ios' ? 'pageSheet' : 'overFullScreen'}
        onRequestClose={() => setSettingsVisible(false)}
      >
        <SafeAreaView style={styles.safeArea}>
          <View style={styles.header}>
            <TouchableOpacity
              style={styles.settingsButton}
              onPress={() => setSettingsVisible(false)}
              hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}
            >
              <Text style={styles.cancelText}>Cancel</Text>
            </TouchableOpacity>
            <View style={styles.headerCenter}>
              <Text style={styles.headerTitle}>Settings</Text>
            </View>
            <View style={styles.headerLeft} />
          </View>
          <SettingsPanel runtime={runtimeRef.current} onSave={handleSettingsSave} />
        </SafeAreaView>
      </Modal>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: '#ffffff',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#e2e8f0',
    backgroundColor: '#ffffff',
  },
  headerLeft: {
    width: 60,
  },
  headerCenter: {
    flex: 1,
    alignItems: 'center',
  },
  headerTitle: {
    fontSize: 17,
    fontWeight: '700',
    color: '#1e293b',
  },
  headerSubtitle: {
    fontSize: 12,
    color: '#64748b',
    marginTop: 1,
  },
  settingsButton: {
    width: 60,
    alignItems: 'flex-end',
  },
  settingsIcon: {
    fontSize: 22,
  },
  cancelText: {
    fontSize: 16,
    color: '#6366f1',
  },
});
