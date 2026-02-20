# pi-mobile

> Inspired by [pi-mono](https://github.com/badlogic/pi-mono) — the mobile equivalent for building LLM-powered chat apps on Android and iOS.

**pi-mobile** provides a lightweight `AgentRuntime` that handles streaming LLM conversations, tool calling, and multi-provider support — all built on React Native / Expo.

---

## Features

- 📱 **Cross-platform** — runs on Android and iOS (and web for development)
- 🤖 **Multi-provider** — OpenAI, Anthropic (Claude), and Google (Gemini) out of the box
- ⚡ **Streaming** — real-time token streaming using the native `fetch` API
- 🔧 **Tool calling** — structured tool definitions with automatic argument validation
- 🧵 **Event-driven** — subscribe to `AgentRuntimeEvent`s to drive reactive UIs
- 🏗️ **Minimal surface area** — zero native modules, pure TypeScript

---

## Quick Start

### Prerequisites

- [Node.js](https://nodejs.org/) 18+
- [Expo CLI](https://docs.expo.dev/get-started/installation/) (`npm install -g expo-cli`)
- An API key from [OpenAI](https://platform.openai.com/), [Anthropic](https://www.anthropic.com/), or [Google AI Studio](https://ai.google.dev/)

### Install & Run

```bash
npm install          # Install dependencies
npm run start        # Start Expo development server
npm run android      # Run on Android (requires Android Studio / emulator)
npm run ios          # Run on iOS (requires macOS + Xcode)
npm run web          # Run in browser (for development)
```

Enter your API key in the **Settings** screen (⚙️ in the top-right corner), then start chatting!

---

## AgentRuntime API

### Instantiation

```ts
import { AgentRuntime, BUILT_IN_MODELS } from './src/agent-runtime';

const runtime = new AgentRuntime({
  model: BUILT_IN_MODELS[0],   // GPT-4o by default
  apiKey: 'sk-...',
  systemPrompt: 'You are a helpful assistant.',
  onEvent: (event) => console.log(event),
});
```

### Sending messages

```ts
// Send a user message and await the full response
await runtime.send('What is the capital of France?');

// Access the full conversation history
console.log(runtime.messages);

// Abort a streaming response
runtime.abort();
```

### Subscribing to events

```ts
const unsubscribe = runtime.subscribe((event) => {
  switch (event.type) {
    case 'message_start':
      console.log('Assistant started responding');
      break;
    case 'message_delta':
      process.stdout.write(event.text); // streaming token
      break;
    case 'message_end':
      console.log('Done:', event.message);
      break;
    case 'error':
      console.error('Error:', event.error);
      break;
  }
});

// Later: remove the listener
unsubscribe();
```

### Tool calling

```ts
import type { AgentTool } from './src/agent-runtime';

const weatherTool: AgentTool = {
  name: 'get_weather',
  description: 'Get the current weather for a city',
  parameters: {
    type: 'object',
    properties: {
      city: { type: 'string', description: 'City name' },
    },
    required: ['city'],
  },
  execute: async (_id, args) => {
    const city = args.city as string;
    return {
      content: [{ type: 'text', text: `Weather in ${city}: 22°C, sunny` }],
    };
  },
};

runtime.setTools([weatherTool]);
await runtime.send('What is the weather in Paris?');
```

### Switching models or providers

```ts
import { BUILT_IN_MODELS } from './src/agent-runtime';

// Switch to Claude 3.5 Sonnet
runtime.setModel(BUILT_IN_MODELS.find((m) => m.id === 'claude-3-5-sonnet-20241022')!);
runtime.setApiKey('sk-ant-...');
runtime.clearMessages(); // optional: start a fresh conversation
```

---

## Built-in Models

| Model | Provider | ID |
|-------|----------|----|
| GPT-4o | OpenAI | `gpt-4o` |
| GPT-4o mini | OpenAI | `gpt-4o-mini` |
| Claude 3.5 Sonnet | Anthropic | `claude-3-5-sonnet-20241022` |
| Claude 3 Haiku | Anthropic | `claude-3-haiku-20240307` |
| Gemini 2.0 Flash | Google | `gemini-2.0-flash` |
| Gemini 1.5 Pro | Google | `gemini-1.5-pro` |

Custom models can be passed directly to `AgentRuntime` using the `Model` type.

---

## Project Structure

```
├── App.tsx                          # Root application component
├── app.json                         # Expo project configuration
├── package.json
├── tsconfig.json
├── assets/                          # App icons and splash screen
└── src/
    ├── agent-runtime/               # AgentRuntime core
    │   ├── index.ts                 # Public exports
    │   ├── types.ts                 # All types (Model, Message, AgentTool, …)
    │   ├── agent-runtime.ts         # AgentRuntime class
    │   ├── stream-parsers.ts        # SSE / NDJSON stream readers
    │   └── providers/
    │       ├── openai.ts            # OpenAI chat completions
    │       ├── anthropic.ts         # Anthropic Messages API
    │       └── google.ts            # Google Generative AI
    └── components/
        ├── ChatView.tsx             # Full chat UI (messages + input bar)
        ├── MessageBubble.tsx        # Individual message bubble
        └── SettingsPanel.tsx        # Model/API key/system prompt config
```

---

## License

MIT
