/**
 * AgentRuntime — the core mobile agent that connects to LLMs and manages
 * conversation state.  Mirrors the pi-mono Agent architecture, adapted for
 * React Native (Android & iOS).
 *
 * Usage
 * -----
 * ```ts
 * const runtime = new AgentRuntime({
 *   model: BUILT_IN_MODELS[0],
 *   apiKey: 'sk-...',
 *   systemPrompt: 'You are a helpful assistant.',
 *   onEvent: (event) => console.log(event),
 * });
 *
 * await runtime.send('Hello!');
 * ```
 */

import type {
  AgentRuntimeEvent,
  AgentRuntimeOptions,
  AgentTool,
  AssistantMessage,
  Message,
  Model,
  StopReason,
  ToolResultMessage,
} from './types';
import { streamOpenAI } from './providers/openai';
import { streamAnthropic } from './providers/anthropic';
import { streamGoogle } from './providers/google';

// Default provider base URLs
const DEFAULT_BASE_URLS: Record<string, string> = {
  openai: 'https://api.openai.com/v1',
  anthropic: 'https://api.anthropic.com/v1',
  google: 'https://generativelanguage.googleapis.com/v1beta',
};

export class AgentRuntime {
  private _model: Model;
  private _apiKey: string;
  private _systemPrompt: string;
  private _tools: AgentTool[];
  private _messages: Message[] = [];
  private _isStreaming = false;
  private _abortController?: AbortController;
  private _onEvent?: (event: AgentRuntimeEvent) => void;
  private _listeners = new Set<(event: AgentRuntimeEvent) => void>();

  constructor(options: AgentRuntimeOptions) {
    this._model = options.model;
    this._apiKey = options.apiKey;
    this._systemPrompt = options.systemPrompt ?? '';
    this._tools = options.tools ?? [];
    if (options.onEvent) {
      this._onEvent = options.onEvent;
    }
  }

  // ─── Getters / Setters ─────────────────────────────────────────────────────

  get model(): Model {
    return this._model;
  }

  setModel(model: Model): void {
    this._model = model;
  }

  get apiKey(): string {
    return this._apiKey;
  }

  setApiKey(key: string): void {
    this._apiKey = key;
  }

  get systemPrompt(): string {
    return this._systemPrompt;
  }

  setSystemPrompt(prompt: string): void {
    this._systemPrompt = prompt;
  }

  get tools(): AgentTool[] {
    return this._tools;
  }

  setTools(tools: AgentTool[]): void {
    this._tools = tools;
  }

  get messages(): Message[] {
    return [...this._messages];
  }

  get isStreaming(): boolean {
    return this._isStreaming;
  }

  // ─── Event subscription ────────────────────────────────────────────────────

  /**
   * Subscribe to runtime events.  Returns an unsubscribe function.
   */
  subscribe(fn: (event: AgentRuntimeEvent) => void): () => void {
    this._listeners.add(fn);
    return () => this._listeners.delete(fn);
  }

  // ─── Conversation management ───────────────────────────────────────────────

  clearMessages(): void {
    this._messages = [];
  }

  /** Abort the current streaming request if one is in progress. */
  abort(): void {
    this._abortController?.abort();
  }

  // ─── Core: send a message ─────────────────────────────────────────────────

  /**
   * Send a user message and stream the assistant response.
   * Resolves when the complete response (including any tool calls) is done.
   *
   * @throws if the runtime is already streaming; call `abort()` first.
   */
  async send(text: string): Promise<void> {
    if (this._isStreaming) {
      throw new Error(
        'AgentRuntime is already streaming.  Call abort() before sending a new message.'
      );
    }

    this._abortController = new AbortController();
    this._isStreaming = true;

    this._messages.push({
      role: 'user',
      content: text,
      timestamp: Date.now(),
    });

    try {
      await this._runLoop(this._abortController.signal);
    } finally {
      this._isStreaming = false;
      this._abortController = undefined;
    }
  }

  // ─── Internal loop (handles tool calls) ───────────────────────────────────

  private async _runLoop(signal: AbortSignal): Promise<void> {
    // Keep looping as long as the model requests tool calls
    while (true) {
      let assistantMessage: AssistantMessage;

      try {
        assistantMessage = await this._streamAssistant(signal);
      } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : String(err);
        const stopReason: StopReason = signal.aborted ? 'aborted' : 'error';
        const errorMessage: AssistantMessage = {
          role: 'assistant',
          content: [{ type: 'text', text: '' }],
          provider: this._model.provider,
          model: this._model.id,
          stopReason,
          errorMessage: msg,
          timestamp: Date.now(),
        };
        this._messages.push(errorMessage);
        this._emit({ type: 'error', error: msg });
        return;
      }

      this._messages.push(assistantMessage);

      // No tool calls — we are done
      if (assistantMessage.stopReason !== 'toolUse') {
        break;
      }

      // Execute tool calls in parallel
      const toolCalls = assistantMessage.content.filter((c) => c.type === 'toolCall');
      if (toolCalls.length === 0) break;

      const toolResultMessages: ToolResultMessage[] = [];

      for (const tc of toolCalls) {
        if (tc.type !== 'toolCall') continue;

        const tool = this._tools.find((t) => t.name === tc.name);

        this._emit({
          type: 'tool_start',
          toolCallId: tc.id,
          toolName: tc.name,
          args: tc.arguments,
        });

        let resultContent: Array<{ type: 'text'; text: string }> = [];
        let isError = false;

        try {
          if (!tool) throw new Error(`Tool "${tc.name}" not found`);
          const result = await tool.execute(tc.id, tc.arguments, signal);
          resultContent = result.content.filter((c) => c.type === 'text') as Array<{
            type: 'text';
            text: string;
          }>;
          isError = result.isError ?? false;
        } catch (err: unknown) {
          resultContent = [{ type: 'text', text: err instanceof Error ? err.message : String(err) }];
          isError = true;
        }

        const toolResult = {
          type: 'toolResult' as const,
          toolCallId: tc.id,
          toolName: tc.name,
          content: resultContent,
          isError,
        };

        this._emit({
          type: 'tool_end',
          toolCallId: tc.id,
          toolName: tc.name,
          result: toolResult,
        });

        toolResultMessages.push({
          role: 'toolResult',
          toolCallId: tc.id,
          toolName: tc.name,
          content: resultContent,
          isError,
          timestamp: Date.now(),
        });
      }

      // Append all tool results to the conversation
      for (const tr of toolResultMessages) {
        this._messages.push(tr);
      }

      if (signal.aborted) break;
    }
  }

  // ─── Stream a single assistant turn ───────────────────────────────────────

  private async _streamAssistant(signal: AbortSignal): Promise<AssistantMessage> {
    const { provider, id: modelId, baseUrl } = this._model;
    const resolvedBaseUrl = baseUrl ?? DEFAULT_BASE_URLS[provider] ?? '';

    let finalMessage: AssistantMessage | null = null;

    const partial: AssistantMessage = {
      role: 'assistant',
      content: [],
      provider,
      model: modelId,
      stopReason: 'stop',
      timestamp: Date.now(),
    };

    this._emit({ type: 'message_start', message: { ...partial } });

    const onDelta = (text: string): void => {
      this._emit({ type: 'message_delta', text, message: { ...partial } });
    };

    const gen = this._createProviderStream(
      provider,
      this._messages,
      modelId,
      this._apiKey,
      resolvedBaseUrl,
      this._systemPrompt || undefined,
      this._tools.length > 0 ? this._tools : undefined,
      signal,
      onDelta
    );

    for await (const msg of gen) {
      finalMessage = msg;
    }

    if (!finalMessage) {
      throw new Error('Provider returned no message');
    }

    this._emit({ type: 'message_end', message: finalMessage });

    return finalMessage;
  }

  private _createProviderStream(
    provider: string,
    messages: Message[],
    modelId: string,
    apiKey: string,
    baseUrl: string,
    systemPrompt: string | undefined,
    tools: AgentTool[] | undefined,
    signal: AbortSignal | undefined,
    onDelta: (text: string) => void
  ): AsyncGenerator<AssistantMessage> {
    switch (provider) {
      case 'openai':
        return streamOpenAI(messages, modelId, apiKey, baseUrl, systemPrompt, tools, signal, onDelta);
      case 'anthropic':
        return streamAnthropic(messages, modelId, apiKey, baseUrl, systemPrompt, tools, signal, onDelta);
      case 'google':
        return streamGoogle(messages, modelId, apiKey, baseUrl, systemPrompt, tools, signal, onDelta);
      default:
        throw new Error(`Unsupported provider: ${provider}`);
    }
  }

  // ─── Internal helpers ──────────────────────────────────────────────────────

  private _emit(event: AgentRuntimeEvent): void {
    this._onEvent?.(event);
    for (const fn of this._listeners) {
      fn(event);
    }
  }
}
