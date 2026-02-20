/**
 * pi-mobile AgentRuntime
 *
 * Public API for the mobile agent runtime.  Import from here in your app code.
 *
 * @example
 * ```ts
 * import { AgentRuntime, BUILT_IN_MODELS } from './src/agent-runtime';
 *
 * const runtime = new AgentRuntime({
 *   model: BUILT_IN_MODELS[0],
 *   apiKey: 'sk-...',
 *   systemPrompt: 'You are a helpful assistant.',
 * });
 *
 * runtime.subscribe((event) => {
 *   if (event.type === 'message_delta') {
 *     process.stdout.write(event.text);
 *   }
 * });
 *
 * await runtime.send('Hello!');
 * ```
 */

export { AgentRuntime } from './agent-runtime';
export type {
  AgentRuntimeEvent,
  AgentRuntimeOptions,
  AgentTool,
  AssistantMessage,
  ImageContent,
  Message,
  Model,
  Provider,
  StopReason,
  TextContent,
  ToolCall,
  ToolResult,
  ToolResultMessage,
  UserMessage,
} from './types';
export { BUILT_IN_MODELS } from './types';
