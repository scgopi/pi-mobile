/**
 * Anthropic Messages streaming provider.
 * Calls the /v1/messages endpoint with stream: true and processes SSE events.
 */

import type { AssistantMessage, Message, AgentTool } from '../types';
import { readSseStream } from '../stream-parsers';

interface AnthropicToolDefinition {
  name: string;
  description: string;
  input_schema: unknown;
}

interface AnthropicContentBlockDelta {
  type: 'content_block_delta';
  index: number;
  delta: { type: 'text_delta'; text: string } | { type: 'input_json_delta'; partial_json: string };
}

interface AnthropicContentBlockStart {
  type: 'content_block_start';
  index: number;
  content_block:
    | { type: 'text'; text: string }
    | { type: 'tool_use'; id: string; name: string; input: unknown };
}

interface AnthropicMessageDelta {
  type: 'message_delta';
  delta: { stop_reason: string | null };
}

type AnthropicSseEvent =
  | AnthropicContentBlockStart
  | AnthropicContentBlockDelta
  | AnthropicMessageDelta
  | { type: string };

export async function* streamAnthropic(
  messages: Message[],
  model: string,
  apiKey: string,
  baseUrl: string,
  systemPrompt: string | undefined,
  tools: AgentTool[] | undefined,
  signal: AbortSignal | undefined,
  onDelta: (text: string) => void
): AsyncGenerator<AssistantMessage> {
  const url = `${baseUrl}/messages`;

  const anthropicMessages: Array<Record<string, unknown>> = [];

  for (const msg of messages) {
    if (msg.role === 'user') {
      if (typeof msg.content === 'string') {
        anthropicMessages.push({ role: 'user', content: msg.content });
      } else {
        const parts = msg.content.map((c) => {
          if (c.type === 'text') return { type: 'text', text: c.text };
          return {
            type: 'image',
            source: { type: 'base64', media_type: c.mimeType, data: c.data },
          };
        });
        anthropicMessages.push({ role: 'user', content: parts });
      }
    } else if (msg.role === 'assistant') {
      const parts: unknown[] = [];
      for (const c of msg.content) {
        if (c.type === 'text') {
          parts.push({ type: 'text', text: c.text });
        } else if (c.type === 'toolCall') {
          parts.push({ type: 'tool_use', id: c.id, name: c.name, input: c.arguments });
        }
      }
      anthropicMessages.push({ role: 'assistant', content: parts });
    } else if (msg.role === 'toolResult') {
      const resultContent = msg.content.map((c) => {
        if (c.type === 'text') return { type: 'text', text: c.text };
        return {
          type: 'image',
          source: { type: 'base64', media_type: c.mimeType, data: c.data },
        };
      });
      // Anthropic expects tool results as a user message with type tool_result
      anthropicMessages.push({
        role: 'user',
        content: [
          {
            type: 'tool_result',
            tool_use_id: msg.toolCallId,
            content: resultContent,
            is_error: msg.isError,
          },
        ],
      });
    }
  }

  const body: Record<string, unknown> = {
    model,
    messages: anthropicMessages,
    max_tokens: 8192,
    stream: true,
  };

  if (systemPrompt) {
    body.system = systemPrompt;
  }

  if (tools && tools.length > 0) {
    const toolDefs: AnthropicToolDefinition[] = tools.map((t) => ({
      name: t.name,
      description: t.description,
      input_schema: t.parameters,
    }));
    body.tools = toolDefs;
  }

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify(body),
    signal,
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Anthropic API error ${response.status}: ${errorText}`);
  }

  if (!response.body) {
    throw new Error('Anthropic response body is null');
  }

  const partial: AssistantMessage = {
    role: 'assistant',
    content: [],
    provider: 'anthropic',
    model,
    stopReason: 'stop',
    timestamp: Date.now(),
  };

  // Builders indexed by content block index
  const textBuilders: Record<number, number> = {}; // index → partial.content index
  const toolBuilders: Record<number, { id: string; name: string; inputRaw: string }> = {};

  for await (const data of readSseStream(response.body, signal)) {
    let event: AnthropicSseEvent;
    try {
      event = JSON.parse(data) as AnthropicSseEvent;
    } catch {
      continue;
    }

    if (event.type === 'content_block_start') {
      const e = event as AnthropicContentBlockStart;
      if (e.content_block.type === 'text') {
        textBuilders[e.index] = partial.content.length;
        partial.content.push({ type: 'text', text: e.content_block.text });
      } else if (e.content_block.type === 'tool_use') {
        toolBuilders[e.index] = {
          id: e.content_block.id,
          name: e.content_block.name,
          inputRaw: '',
        };
      }
    } else if (event.type === 'content_block_delta') {
      const e = event as AnthropicContentBlockDelta;
      if (e.delta.type === 'text_delta') {
        const contentIndex = textBuilders[e.index];
        if (contentIndex !== undefined) {
          const block = partial.content[contentIndex];
          if (block.type === 'text') {
            block.text += e.delta.text;
            onDelta(e.delta.text);
          }
        }
      } else if (e.delta.type === 'input_json_delta') {
        if (toolBuilders[e.index]) {
          toolBuilders[e.index].inputRaw += e.delta.partial_json;
        }
      }
    } else if (event.type === 'message_delta') {
      const e = event as AnthropicMessageDelta;
      const reason = e.delta.stop_reason;
      if (reason === 'tool_use') {
        partial.stopReason = 'toolUse';
      } else if (reason === 'max_tokens') {
        partial.stopReason = 'length';
      } else {
        partial.stopReason = 'stop';
      }
    }
  }

  // Finalise tool call blocks
  for (const builder of Object.values(toolBuilders)) {
    let parsedArgs: Record<string, unknown> = {};
    try {
      parsedArgs = JSON.parse(builder.inputRaw) as Record<string, unknown>;
    } catch {
      parsedArgs = { raw: builder.inputRaw };
    }
    partial.content.push({
      type: 'toolCall',
      id: builder.id,
      name: builder.name,
      arguments: parsedArgs,
    });
  }

  yield partial;
}
