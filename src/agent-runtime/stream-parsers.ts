/**
 * Lightweight Server-Sent Events (SSE) parser for streaming LLM responses.
 * Processes raw text chunks from a fetch ReadableStream into SSE data lines.
 */

/**
 * Parse a raw SSE chunk into individual `data:` payloads.
 * Returns an array of data strings (excluding the "data: " prefix).
 */
export function parseSseChunk(chunk: string): string[] {
  const lines = chunk.split('\n');
  const dataLines: string[] = [];
  for (const line of lines) {
    if (line.startsWith('data: ')) {
      dataLines.push(line.slice(6));
    }
  }
  return dataLines;
}

/**
 * Async generator that reads an SSE response body and yields decoded text chunks.
 * Each yielded string is the raw JSON payload (without the "data: " prefix).
 *
 * @param body  - The ReadableStream<Uint8Array> from a fetch response
 * @param signal - Optional AbortSignal to cancel mid-stream
 */
export async function* readSseStream(
  body: ReadableStream<Uint8Array>,
  signal?: AbortSignal
): AsyncGenerator<string> {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';

  try {
    while (true) {
      if (signal?.aborted) {
        reader.cancel();
        break;
      }

      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });

      // Split on double newlines (SSE event separator) or process line by line
      const parts = buffer.split('\n');
      // Keep the last potentially incomplete line in the buffer
      buffer = parts.pop() ?? '';

      for (const line of parts) {
        if (line.startsWith('data: ')) {
          const data = line.slice(6).trim();
          if (data && data !== '[DONE]') {
            yield data;
          }
        }
      }
    }

    // Flush remaining buffer
    if (buffer.startsWith('data: ')) {
      const data = buffer.slice(6).trim();
      if (data && data !== '[DONE]') {
        yield data;
      }
    }
  } finally {
    reader.releaseLock();
  }
}

/**
 * Async generator that reads a newline-delimited JSON (NDJSON) response body.
 * Used by the Google Generative AI streaming endpoint.
 *
 * @param body  - The ReadableStream<Uint8Array> from a fetch response
 * @param signal - Optional AbortSignal to cancel mid-stream
 */
export async function* readNdjsonStream(
  body: ReadableStream<Uint8Array>,
  signal?: AbortSignal
): AsyncGenerator<string> {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';

  try {
    while (true) {
      if (signal?.aborted) {
        reader.cancel();
        break;
      }

      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });

      const lines = buffer.split('\n');
      buffer = lines.pop() ?? '';

      for (const line of lines) {
        const trimmed = line.trim();
        // Google streams comma-separated JSON objects inside an array
        // Strip leading/trailing array brackets and commas
        const cleaned = trimmed.replace(/^[\[,]/, '').replace(/\]$/, '').trim();
        if (cleaned) {
          yield cleaned;
        }
      }
    }

    if (buffer.trim()) {
      const cleaned = buffer.trim().replace(/^[\[,]/, '').replace(/\]$/, '').trim();
      if (cleaned) {
        yield cleaned;
      }
    }
  } finally {
    reader.releaseLock();
  }
}
