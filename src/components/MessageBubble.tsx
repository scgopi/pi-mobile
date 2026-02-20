import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  ActivityIndicator,
} from 'react-native';
import type { Message } from '../agent-runtime/types';

interface Props {
  message: Message;
  /** When true, shows a blinking cursor after the text (streaming indicator) */
  isStreaming?: boolean;
}

export function MessageBubble({ message, isStreaming = false }: Props): React.ReactElement | null {
  if (message.role === 'toolResult') {
    const text = message.content
      .filter((c) => c.type === 'text')
      .map((c) => (c.type === 'text' ? c.text : ''))
      .join('');
    return (
      <View style={styles.toolResultContainer}>
        <Text style={styles.toolName}>Tool: {message.toolName}</Text>
        <Text style={styles.toolResultText}>{text}</Text>
      </View>
    );
  }

  const isUser = message.role === 'user';
  const isAssistant = message.role === 'assistant';

  let text = '';
  let hasError = false;

  if (isUser) {
    text =
      typeof message.content === 'string'
        ? message.content
        : message.content
            .filter((c) => c.type === 'text')
            .map((c) => (c.type === 'text' ? c.text : ''))
            .join('');
  } else if (isAssistant) {
    text = message.content
      .filter((c) => c.type === 'text')
      .map((c) => (c.type === 'text' ? c.text : ''))
      .join('');
    hasError = message.stopReason === 'error' || message.stopReason === 'aborted';
  }

  if (!text && isAssistant && isStreaming) {
    return (
      <View style={[styles.bubble, styles.assistantBubble]}>
        <ActivityIndicator size="small" color="#6366f1" />
      </View>
    );
  }

  if (!text) return null;

  return (
    <View
      style={[
        styles.bubble,
        isUser ? styles.userBubble : styles.assistantBubble,
        hasError && styles.errorBubble,
      ]}
    >
      <Text style={[styles.text, isUser ? styles.userText : styles.assistantText]}>
        {text}
        {isStreaming && isAssistant && (
          <Text style={styles.cursor}>▊</Text>
        )}
      </Text>
      {hasError && message.role === 'assistant' && message.errorMessage && (
        <Text style={styles.errorText}>{message.errorMessage}</Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  bubble: {
    maxWidth: '80%',
    borderRadius: 16,
    paddingHorizontal: 14,
    paddingVertical: 10,
    marginBottom: 8,
  },
  userBubble: {
    alignSelf: 'flex-end',
    backgroundColor: '#6366f1',
  },
  assistantBubble: {
    alignSelf: 'flex-start',
    backgroundColor: '#f1f5f9',
  },
  errorBubble: {
    backgroundColor: '#fee2e2',
  },
  text: {
    fontSize: 16,
    lineHeight: 22,
  },
  userText: {
    color: '#ffffff',
  },
  assistantText: {
    color: '#1e293b',
  },
  cursor: {
    color: '#6366f1',
  },
  errorText: {
    marginTop: 4,
    fontSize: 12,
    color: '#ef4444',
  },
  toolResultContainer: {
    alignSelf: 'flex-start',
    backgroundColor: '#f8fafc',
    borderLeftWidth: 3,
    borderLeftColor: '#94a3b8',
    borderRadius: 4,
    paddingHorizontal: 12,
    paddingVertical: 8,
    marginBottom: 8,
    maxWidth: '90%',
  },
  toolName: {
    fontSize: 12,
    color: '#64748b',
    fontWeight: '600',
    marginBottom: 4,
  },
  toolResultText: {
    fontSize: 14,
    color: '#334155',
  },
});
