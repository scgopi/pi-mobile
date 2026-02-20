import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  FlatList,
  KeyboardAvoidingView,
  Platform,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import type { AgentRuntime } from '../agent-runtime/agent-runtime';
import type { AssistantMessage, Message } from '../agent-runtime/types';
import { MessageBubble } from './MessageBubble';

interface Props {
  runtime: AgentRuntime;
}

export function ChatView({ runtime }: Props): React.ReactElement {
  const [messages, setMessages] = useState<Message[]>(runtime.messages);
  const [streamingMessage, setStreamingMessage] = useState<AssistantMessage | null>(null);
  const [inputText, setInputText] = useState('');
  const [isStreaming, setIsStreaming] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const flatListRef = useRef<FlatList>(null);

  // Subscribe to runtime events
  useEffect(() => {
    const unsubscribe = runtime.subscribe((event) => {
      switch (event.type) {
        case 'message_start':
          setIsStreaming(true);
          setStreamingMessage({ ...event.message });
          break;

        case 'message_delta': {
          setStreamingMessage((prev) => {
            if (!prev) return { ...event.message };
            // Append delta text to the current streaming message
            const updatedContent = prev.content.map((c, i) => {
              if (i === prev.content.length - 1 && c.type === 'text') {
                return { ...c, text: c.text + event.text };
              }
              return c;
            });
            if (updatedContent.length === 0 || updatedContent[0].type !== 'text') {
              return { ...prev, content: [{ type: 'text', text: event.text }] };
            }
            return { ...prev, content: updatedContent };
          });
          break;
        }

        case 'message_end':
          setStreamingMessage(null);
          setMessages([...runtime.messages]);
          setIsStreaming(false);
          break;

        case 'error':
          setError(event.error);
          setIsStreaming(false);
          setStreamingMessage(null);
          setMessages([...runtime.messages]);
          break;

        default:
          break;
      }
    });

    return unsubscribe;
  }, [runtime]);

  // Auto-scroll to bottom
  useEffect(() => {
    setTimeout(() => {
      flatListRef.current?.scrollToEnd({ animated: true });
    }, 50);
  }, [messages, streamingMessage]);

  const handleSend = useCallback(async () => {
    const text = inputText.trim();
    if (!text || isStreaming) return;

    setInputText('');
    setError(null);

    // Optimistically add user message to list
    setMessages((prev) => [
      ...prev,
      { role: 'user', content: text, timestamp: Date.now() },
    ]);

    try {
      await runtime.send(text);
      setMessages([...runtime.messages]);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      setError(msg);
    }
  }, [inputText, isStreaming, runtime]);

  const handleAbort = useCallback(() => {
    runtime.abort();
  }, [runtime]);

  // Combine committed messages with the current streaming message for display
  const displayMessages: Message[] = streamingMessage
    ? [...messages, streamingMessage]
    : messages;

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
      keyboardVerticalOffset={Platform.OS === 'ios' ? 90 : 0}
    >
      <FlatList
        ref={flatListRef}
        data={displayMessages}
        keyExtractor={(_, index) => String(index)}
        renderItem={({ item, index }) => (
          <MessageBubble
            message={item}
            isStreaming={
              streamingMessage !== null &&
              index === displayMessages.length - 1 &&
              item.role === 'assistant'
            }
          />
        )}
        contentContainerStyle={styles.messageList}
        showsVerticalScrollIndicator={false}
      />

      {error && (
        <View style={styles.errorBanner}>
          <Text style={styles.errorBannerText}>{error}</Text>
        </View>
      )}

      <View style={styles.inputRow}>
        <TextInput
          style={styles.input}
          value={inputText}
          onChangeText={setInputText}
          placeholder="Message…"
          placeholderTextColor="#94a3b8"
          multiline
          maxLength={4000}
          editable={!isStreaming}
          onSubmitEditing={handleSend}
          returnKeyType="send"
          blurOnSubmit={false}
        />
        {isStreaming ? (
          <TouchableOpacity style={styles.sendButton} onPress={handleAbort}>
            <Text style={styles.sendButtonText}>Stop</Text>
          </TouchableOpacity>
        ) : (
          <TouchableOpacity
            style={[styles.sendButton, !inputText.trim() && styles.sendButtonDisabled]}
            onPress={handleSend}
            disabled={!inputText.trim()}
          >
            <Text style={styles.sendButtonText}>Send</Text>
          </TouchableOpacity>
        )}
      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#ffffff',
  },
  messageList: {
    paddingHorizontal: 16,
    paddingVertical: 12,
    flexGrow: 1,
    justifyContent: 'flex-end',
  },
  errorBanner: {
    backgroundColor: '#fee2e2',
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  errorBannerText: {
    color: '#dc2626',
    fontSize: 13,
  },
  inputRow: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: '#e2e8f0',
    backgroundColor: '#ffffff',
  },
  input: {
    flex: 1,
    minHeight: 40,
    maxHeight: 120,
    backgroundColor: '#f8fafc',
    borderRadius: 20,
    paddingHorizontal: 16,
    paddingVertical: 10,
    fontSize: 16,
    color: '#1e293b',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: '#e2e8f0',
  },
  sendButton: {
    marginLeft: 10,
    height: 40,
    paddingHorizontal: 18,
    borderRadius: 20,
    backgroundColor: '#6366f1',
    alignItems: 'center',
    justifyContent: 'center',
  },
  sendButtonDisabled: {
    backgroundColor: '#c7d2fe',
  },
  sendButtonText: {
    color: '#ffffff',
    fontWeight: '600',
    fontSize: 15,
  },
});
