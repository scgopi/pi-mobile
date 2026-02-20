# pi-mobile Architecture

## Overview

pi-mobile brings Mario Zechner's Pi agent philosophy (radically minimal architecture) to native Android and iOS. Instead of a CLI coding agent, it's a **mobile AI assistant that operates on local data, files, and SQLite databases** through a chat-based UX.

## Monorepo Structure

```
pi-mobile/
├── shared/                    # JSON specs & schemas (not code)
│   ├── model-catalogue.json   # Model definitions across providers
│   ├── tool-schemas/          # JSON Schema for each built-in tool
│   ├── system-prompt.txt      # Default system prompt (<1000 tokens)
│   └── test-fixtures/         # Shared test data
├── android/                   # Kotlin + Jetpack Compose
│   ├── pi-ai/                 # Foundation: LLM abstraction
│   ├── pi-agent-core/         # Core: Agent loop + tool system
│   ├── pi-tools/              # Core: 7 built-in tools
│   ├── pi-session/            # Core: SQLite DAG session storage
│   ├── pi-extensions/         # Core: Extension loading
│   └── pi-app/                # App: Chat UI + DI
├── ios/                       # Swift + SwiftUI
│   ├── PiAI/                  # Foundation: LLM abstraction
│   ├── PiAgentCore/           # Core: Agent loop + tool system
│   ├── PiTools/               # Core: 7 built-in tools
│   ├── PiSession/             # Core: SQLite DAG session storage
│   ├── PiExtensions/          # Core: Extension loading
│   └── PiApp/                 # App: Chat UI + DI
└── docs/                      # Architecture documentation
```

## Dependency Graph

```
pi-app  →  pi-agent-core, pi-tools, pi-session, pi-extensions
                ↓                        ↓
              pi-ai (foundation, zero internal deps)
```

## Layer Descriptions

### Foundation: pi-ai / PiAI
- Portable types: ModelDefinition, Context, Message, StreamEvent
- 4 wire protocol adapters: OpenAI Completions, OpenAI Responses, Anthropic, Google
- Provider quirk handling (Cerebras, Mistral, xAI, etc.)
- Streaming via OkHttp SSE (Android) / URLSession bytes (iOS)
- Model catalogue: 300+ models loaded from JSON

### Core: pi-agent-core / PiAgentCore
- Tool interface with JSON Schema validation
- AgentLoop: stream → check tool calls → execute → append → repeat
- AgentEvent sealed hierarchy for UI consumption
- Rich tool results: File, Diff, Table, Error

### Core: pi-tools / PiTools
7 built-in tools replacing Pi's original 4:
1. read_file — sandbox + user-granted file access
2. write_file — sandbox-restricted file creation
3. edit_file — surgical search/replace with diff
4. list_files — directory listing with glob
5. sqlite_query — SQL on any SQLite database
6. http_request — HTTP client
7. media_query — device photos/video/audio via MediaStore/Photos

### Core: pi-session / PiSession
- SQLite DAG for conversation branching
- Sessions with leaf pointers, entries as DAG nodes
- Recursive CTE for branch reconstruction
- WAL mode for concurrent access
- Room (Android) / GRDB (iOS)

### Core: pi-extensions / PiExtensions
- Extension interface with lifecycle hooks
- Tool aggregation from extensions
- JSON-defined declarative extensions
- ToolCallDecision: Allow / Block / Modify

### App: pi-app / PiApp
- MVVM + unidirectional data flow
- Streaming markdown rendering
- Rich tool result cards (syntax highlight, diff view, table)
- Session list with branching
- API key management (Keystore/Keychain)
- Material 3 (Android) / native SwiftUI (iOS)

## Wire Protocols

| Protocol | Endpoint | Providers |
|---|---|---|
| openai-completions | /v1/chat/completions | OpenAI, Groq, Together, Cerebras, Mistral, xAI, DeepSeek |
| openai-responses | /v1/responses | OpenAI (newer) |
| anthropic | /v1/messages | Anthropic |
| google | /v1beta/models/{model}:generateContent | Google Gemini |
| azure | /openai/deployments/{model}/chat/completions | Azure OpenAI |

## Security

See [SECURITY.md](../SECURITY.md) for details on the security model, including API key storage, file sandboxing, and responsible disclosure.

## System Prompt

Under 1,000 tokens. See `shared/system-prompt.txt`.
