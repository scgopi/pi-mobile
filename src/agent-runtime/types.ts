/**
 * Core types for the pi-mobile AgentRuntime.
 * Mirrors the pi-mono agent architecture adapted for mobile.
 */

// ─── Provider & Model ────────────────────────────────────────────────────────

export type Provider = 'openai' | 'anthropic' | 'google';

export type Api =
  | 'openai-completions'
  | 'anthropic-messages'
  | 'google-generative-ai';

export interface Model {
  /** Model identifier used by the provider (e.g. "gpt-4o") */
  id: string;
  /** Human-readable display name */
  name: string;
  /** LLM provider */
  provider: Provider;
  /** API protocol used to talk to the provider */
  api: Api;
  /** Optional custom base URL (defaults to the provider's public endpoint) */
  baseUrl?: string;
  /** Maximum output tokens supported by the model */
  maxTokens?: number;
  /** Context window size in tokens */
  contextWindow?: number;
}

// ─── Message Content ─────────────────────────────────────────────────────────

export interface TextContent {
  type: 'text';
  text: string;
}

export interface ImageContent {
  type: 'image';
  /** Base64-encoded image data */
  data: string;
  mimeType: string;
}

export interface ToolCall {
  type: 'toolCall';
  id: string;
  name: string;
  arguments: Record<string, unknown>;
}

export interface ToolResult {
  type: 'toolResult';
  toolCallId: string;
  content: (TextContent | ImageContent)[];
  isError: boolean;
}

// ─── Messages ────────────────────────────────────────────────────────────────

export interface UserMessage {
  role: 'user';
  content: string | (TextContent | ImageContent)[];
  timestamp: number;
}

export interface AssistantMessage {
  role: 'assistant';
  content: (TextContent | ToolCall)[];
  provider: Provider;
  model: string;
  stopReason: StopReason;
  errorMessage?: string;
  timestamp: number;
}

export interface ToolResultMessage {
  role: 'toolResult';
  toolCallId: string;
  toolName: string;
  content: (TextContent | ImageContent)[];
  isError: boolean;
  timestamp: number;
}

export type Message = UserMessage | AssistantMessage | ToolResultMessage;

export type StopReason = 'stop' | 'length' | 'toolUse' | 'error' | 'aborted';

// ─── Tools ───────────────────────────────────────────────────────────────────

export interface ToolParameter {
  type: string;
  description?: string;
  enum?: string[];
  properties?: Record<string, ToolParameter>;
  required?: string[];
  items?: ToolParameter;
}

export interface ToolSchema {
  type: 'object';
  properties: Record<string, ToolParameter>;
  required?: string[];
}

export interface AgentTool {
  name: string;
  description: string;
  /** JSON Schema for the tool's parameters */
  parameters: ToolSchema;
  execute: (
    toolCallId: string,
    args: Record<string, unknown>,
    signal?: AbortSignal
  ) => Promise<{ content: (TextContent | ImageContent)[]; isError?: boolean }>;
}

// ─── Events ──────────────────────────────────────────────────────────────────

export type AgentRuntimeEvent =
  | { type: 'message_start'; message: AssistantMessage }
  | { type: 'message_delta'; text: string; message: AssistantMessage }
  | { type: 'message_end'; message: AssistantMessage }
  | { type: 'tool_start'; toolCallId: string; toolName: string; args: Record<string, unknown> }
  | { type: 'tool_end'; toolCallId: string; toolName: string; result: ToolResult }
  | { type: 'error'; error: string };

// ─── Runtime Options ─────────────────────────────────────────────────────────

export interface AgentRuntimeOptions {
  /** Model to use for inference */
  model: Model;
  /** API key for the selected provider */
  apiKey: string;
  /** Optional system prompt injected at the start of every conversation */
  systemPrompt?: string;
  /** Tools available to the model */
  tools?: AgentTool[];
  /**
   * Callback fired on each runtime event (streaming deltas, tool calls, errors).
   * Use this to drive UI updates.
   */
  onEvent?: (event: AgentRuntimeEvent) => void;
}

// ─── Built-in Model Registry ─────────────────────────────────────────────────

export const BUILT_IN_MODELS: Model[] = [
  // OpenAI
  {
    id: 'gpt-4o',
    name: 'GPT-4o',
    provider: 'openai',
    api: 'openai-completions',
    maxTokens: 16384,
    contextWindow: 128000,
  },
  {
    id: 'gpt-4o-mini',
    name: 'GPT-4o mini',
    provider: 'openai',
    api: 'openai-completions',
    maxTokens: 16384,
    contextWindow: 128000,
  },
  // Anthropic
  {
    id: 'claude-3-5-sonnet-20241022',
    name: 'Claude 3.5 Sonnet',
    provider: 'anthropic',
    api: 'anthropic-messages',
    maxTokens: 8192,
    contextWindow: 200000,
  },
  {
    id: 'claude-3-haiku-20240307',
    name: 'Claude 3 Haiku',
    provider: 'anthropic',
    api: 'anthropic-messages',
    maxTokens: 4096,
    contextWindow: 200000,
  },
  // Google
  {
    id: 'gemini-2.0-flash',
    name: 'Gemini 2.0 Flash',
    provider: 'google',
    api: 'google-generative-ai',
    maxTokens: 8192,
    contextWindow: 1048576,
  },
  {
    id: 'gemini-1.5-pro',
    name: 'Gemini 1.5 Pro',
    provider: 'google',
    api: 'google-generative-ai',
    maxTokens: 8192,
    contextWindow: 2097152,
  },
];
