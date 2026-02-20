/**
 * Google Generative AI streaming provider.
 * Calls the streamGenerateContent endpoint and processes the response.
 */

import type { AssistantMessage, Message, AgentTool } from '../types';
import { readNdjsonStream } from '../stream-parsers';

interface GeminiPart {
  text?: string;
  functionCall?: {
    name: string;
    args: Record<string, unknown>;
  };
  inlineData?: {
    mimeType: string;
    data: string;
  };
}

interface GeminiContent {
  role: string;
  parts: GeminiPart[];
}

interface GeminiFunctionDeclaration {
  name: string;
  description: string;
  parameters: unknown;
}

interface GeminiCandidate {
  content: GeminiContent;
  finishReason?: string;
}

interface GeminiResponse {
  candidates?: GeminiCandidate[];
}

export async function* streamGoogle(
  messages: Message[],
  model: string,
  apiKey: string,
  baseUrl: string,
  systemPrompt: string | undefined,
  tools: AgentTool[] | undefined,
  signal: AbortSignal | undefined,
  onDelta: (text: string) => void
): AsyncGenerator<AssistantMessage> {
  const url = `${baseUrl}/models/${model}:streamGenerateContent?key=${encodeURIComponent(apiKey)}&alt=sse`;

  const geminiContents: GeminiContent[] = [];

  for (const msg of messages) {
    if (msg.role === 'user') {
      if (typeof msg.content === 'string') {
        geminiContents.push({ role: 'user', parts: [{ text: msg.content }] });
      } else {
        const parts: GeminiPart[] = msg.content.map((c) => {
          if (c.type === 'text') return { text: c.text };
          return { inlineData: { mimeType: c.mimeType, data: c.data } };
        });
        geminiContents.push({ role: 'user', parts });
      }
    } else if (msg.role === 'assistant') {
      const parts: GeminiPart[] = [];
      for (const c of msg.content) {
        if (c.type === 'text') {
          parts.push({ text: c.text });
        } else if (c.type === 'toolCall') {
          parts.push({ functionCall: { name: c.name, args: c.arguments } });
        }
      }
      geminiContents.push({ role: 'model', parts });
    } else if (msg.role === 'toolResult') {
      const responseText = msg.content
        .filter((c) => c.type === 'text')
        .map((c) => (c.type === 'text' ? c.text : ''))
        .join('');
      geminiContents.push({
        role: 'user',
        parts: [
          {
            // Gemini uses functionResponse for tool results
            // @ts-expect-error Gemini-specific part type
            functionResponse: {
              name: msg.toolName,
              response: { result: responseText },
            },
          },
        ],
      });
    }
  }

  const body: Record<string, unknown> = {
    contents: geminiContents,
  };

  if (systemPrompt) {
    body.systemInstruction = { parts: [{ text: systemPrompt }] };
  }

  if (tools && tools.length > 0) {
    const declarations: GeminiFunctionDeclaration[] = tools.map((t) => ({
      name: t.name,
      description: t.description,
      parameters: t.parameters,
    }));
    body.tools = [{ functionDeclarations: declarations }];
  }

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
    signal,
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Google API error ${response.status}: ${errorText}`);
  }

  if (!response.body) {
    throw new Error('Google response body is null');
  }

  const partial: AssistantMessage = {
    role: 'assistant',
    content: [],
    provider: 'google',
    model,
    stopReason: 'stop',
    timestamp: Date.now(),
  };

  let currentTextIndex = -1;

  for await (const data of readNdjsonStream(response.body, signal)) {
    let chunk: GeminiResponse;
    try {
      chunk = JSON.parse(data) as GeminiResponse;
    } catch {
      continue;
    }

    const candidate = chunk.candidates?.[0];
    if (!candidate) continue;

    for (const part of candidate.content?.parts ?? []) {
      if (part.text !== undefined) {
        if (currentTextIndex === -1) {
          currentTextIndex = partial.content.length;
          partial.content.push({ type: 'text', text: '' });
        }
        const textBlock = partial.content[currentTextIndex];
        if (textBlock.type === 'text') {
          textBlock.text += part.text;
          onDelta(part.text);
        }
      } else if (part.functionCall) {
        partial.content.push({
          type: 'toolCall',
          id: `${part.functionCall.name}-${Date.now()}`,
          name: part.functionCall.name,
          arguments: part.functionCall.args,
        });
      }
    }

    const finishReason = candidate.finishReason;
    if (finishReason === 'MAX_TOKENS') {
      partial.stopReason = 'length';
    } else if (finishReason === 'STOP') {
      partial.stopReason = 'stop';
    } else if (finishReason === 'OTHER' || finishReason === 'SAFETY') {
      partial.stopReason = 'stop';
    }
  }

  // If there are tool calls, update stop reason
  if (partial.content.some((c) => c.type === 'toolCall')) {
    partial.stopReason = 'toolUse';
  }

  yield partial;
}
