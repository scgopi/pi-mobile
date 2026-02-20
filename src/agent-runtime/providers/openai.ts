/**
 * OpenAI chat completions streaming provider.
 * Calls the /v1/chat/completions endpoint with stream: true
 * and yields partial AssistantMessage events.
 */

import type { AssistantMessage, Message, AgentTool } from '../types';
import { readSseStream } from '../stream-parsers';

interface OpenAIToolDefinition {
  type: 'function';
  function: {
    name: string;
    description: string;
    parameters: unknown;
  };
}

interface OpenAIDelta {
  role?: string;
  content?: string | null;
  tool_calls?: Array<{
    index: number;
    id?: string;
    type?: string;
    function?: {
      name?: string;
      arguments?: string;
    };
  }>;
}

interface OpenAIChunk {
  choices: Array<{
    delta: OpenAIDelta;
    finish_reason: string | null;
  }>;
}

export async function* streamOpenAI(
  messages: Message[],
  model: string,
  apiKey: string,
  baseUrl: string,
  systemPrompt: string | undefined,
  tools: AgentTool[] | undefined,
  signal: AbortSignal | undefined,
  onDelta: (text: string) => void
): AsyncGenerator<AssistantMessage> {
  const url = `${baseUrl}/chat/completions`;

  const openAIMessages: Array<Record<string, unknown>> = [];

  if (systemPrompt) {
    openAIMessages.push({ role: 'system', content: systemPrompt });
  }

  for (const msg of messages) {
    if (msg.role === 'user') {
      if (typeof msg.content === 'string') {
        openAIMessages.push({ role: 'user', content: msg.content });
      } else {
        const parts = msg.content.map((c) => {
          if (c.type === 'text') return { type: 'text', text: c.text };
          return {
            type: 'image_url',
            image_url: { url: `data:${c.mimeType};base64,${c.data}` },
          };
        });
        openAIMessages.push({ role: 'user', content: parts });
      }
    } else if (msg.role === 'assistant') {
      const textContent = msg.content
        .filter((c) => c.type === 'text')
        .map((c) => (c.type === 'text' ? c.text : ''))
        .join('');
      const toolCalls = msg.content
        .filter((c) => c.type === 'toolCall')
        .map((c) => {
          if (c.type !== 'toolCall') return null;
          return {
            id: c.id,
            type: 'function',
            function: { name: c.name, arguments: JSON.stringify(c.arguments) },
          };
        })
        .filter(Boolean);
      const entry: Record<string, unknown> = { role: 'assistant', content: textContent || null };
      if (toolCalls.length > 0) entry.tool_calls = toolCalls;
      openAIMessages.push(entry);
    } else if (msg.role === 'toolResult') {
      openAIMessages.push({
        role: 'tool',
        tool_call_id: msg.toolCallId,
        content: msg.content.map((c) => (c.type === 'text' ? c.text : '')).join(''),
      });
    }
  }

  const body: Record<string, unknown> = {
    model,
    messages: openAIMessages,
    stream: true,
  };

  if (tools && tools.length > 0) {
    const toolDefs: OpenAIToolDefinition[] = tools.map((t) => ({
      type: 'function',
      function: {
        name: t.name,
        description: t.description,
        parameters: t.parameters,
      },
    }));
    body.tools = toolDefs;
    body.tool_choice = 'auto';
  }

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify(body),
    signal,
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`OpenAI API error ${response.status}: ${errorText}`);
  }

  if (!response.body) {
    throw new Error('OpenAI response body is null');
  }

  const partial: AssistantMessage = {
    role: 'assistant',
    content: [],
    provider: 'openai',
    model,
    stopReason: 'stop',
    timestamp: Date.now(),
  };

  // Track in-progress tool calls indexed by their position
  const toolCallBuilders: Record<
    number,
    { id: string; name: string; argumentsRaw: string }
  > = {};
  let currentTextIndex = -1;

  for await (const data of readSseStream(response.body, signal)) {
    let chunk: OpenAIChunk;
    try {
      chunk = JSON.parse(data) as OpenAIChunk;
    } catch {
      continue;
    }

    const choice = chunk.choices?.[0];
    if (!choice) continue;

    const delta = choice.delta;

    if (delta.content) {
      if (currentTextIndex === -1) {
        currentTextIndex = partial.content.length;
        partial.content.push({ type: 'text', text: '' });
      }
      const textBlock = partial.content[currentTextIndex];
      if (textBlock.type === 'text') {
        textBlock.text += delta.content;
        onDelta(delta.content);
      }
    }

    if (delta.tool_calls) {
      for (const tc of delta.tool_calls) {
        if (!toolCallBuilders[tc.index]) {
          toolCallBuilders[tc.index] = { id: '', name: '', argumentsRaw: '' };
        }
        if (tc.id) toolCallBuilders[tc.index].id = tc.id;
        if (tc.function?.name) toolCallBuilders[tc.index].name += tc.function.name;
        if (tc.function?.arguments) toolCallBuilders[tc.index].argumentsRaw += tc.function.arguments;
      }
    }

    if (choice.finish_reason === 'tool_calls') {
      partial.stopReason = 'toolUse';
    } else if (choice.finish_reason === 'length') {
      partial.stopReason = 'length';
    } else if (choice.finish_reason === 'stop') {
      partial.stopReason = 'stop';
    }
  }

  // Finalise tool call content
  for (const builder of Object.values(toolCallBuilders)) {
    let parsedArgs: Record<string, unknown> = {};
    try {
      parsedArgs = JSON.parse(builder.argumentsRaw) as Record<string, unknown>;
    } catch {
      parsedArgs = { raw: builder.argumentsRaw };
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
