# pi-mobile

> Native mobile AI assistant for iOS and Android — chat with 300+ LLMs to work with local files, databases, and media.

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![iOS](https://img.shields.io/badge/iOS-17+-black?logo=apple)](ios/)
[![Android](https://img.shields.io/badge/Android-8.0+-green?logo=android)](android/)

## Overview

pi-mobile is a native mobile AI assistant that lets you interact with 300+ large language models through a chat-based interface. The LLM can operate on your local files, SQLite databases, and device media using a set of built-in tools.

- **Native iOS (Swift/SwiftUI) + Android (Kotlin/Jetpack Compose)** — no web views, no Electron
- **Chat-based UX** for natural interaction with LLMs
- **On-device tools:** read/write/edit files, SQL queries, HTTP requests, media queries
- **300+ models** across 10+ providers (OpenAI, Anthropic, Google, Groq, Together, Cerebras, Mistral, xAI, DeepSeek, Azure)
- **Extension system** for adding custom tools

## Architecture

```
pi-app  →  pi-agent-core, pi-tools, pi-session, pi-extensions
                ↓                        ↓
              pi-ai (foundation, zero internal deps)
```

| Module | iOS | Android | Description |
|--------|-----|---------|-------------|
| pi-ai / PiAI | Swift | Kotlin | LLM abstraction: types, adapters, streaming |
| pi-agent-core / PiAgentCore | Swift | Kotlin | Agent loop, tool protocol, JSON Schema validation |
| pi-tools / PiTools | Swift | Kotlin | 7 built-in tools (file, SQL, HTTP, media) |
| pi-session / PiSession | Swift | Kotlin | SQLite DAG session storage (GRDB / Room) |
| pi-extensions / PiExtensions | Swift | Kotlin | Extension loading, lifecycle hooks, tool aggregation |
| pi-app / PiApp | SwiftUI | Compose | Chat UI, settings, API key management |

## Supported Providers

| Protocol | Endpoint | Providers |
|---|---|---|
| openai-completions | `/v1/chat/completions` | OpenAI, Groq, Together, Cerebras, Mistral, xAI, DeepSeek |
| openai-responses | `/v1/responses` | OpenAI (newer) |
| anthropic | `/v1/messages` | Anthropic |
| google | `/v1beta/models/{model}:generateContent` | Google Gemini |

## Built-in Tools

| Tool | Description |
|------|-------------|
| `read_file` | Read file contents with sandbox-restricted, user-granted file access |
| `write_file` | Create or overwrite files within the sandbox |
| `edit_file` | Surgical search-and-replace edits with diff output |
| `list_files` | Directory listing with glob pattern support |
| `sqlite_query` | Execute SQL queries on any SQLite database |
| `http_request` | Make HTTP requests to any URL |
| `media_query` | Query device photos, video, and audio via MediaStore (Android) / Photos framework (iOS) |

## Getting Started

### Prerequisites

- **iOS:** Xcode 15.4+, iOS 17+
- **Android:** Android Studio, JDK 17, Android 8.0+ (API 26)

### Build iOS

```bash
cd ios && swift build
```

### Build Android

```bash
cd android && ./gradlew assembleDebug
```

### API Key Setup

API keys are entered in the app's **Settings** screen. Each provider has its own key field. Keys are stored securely using the iOS Keychain or Android EncryptedSharedPreferences — they never leave the device and are not included in backups.

## Project Structure

```
pi-mobile/
├── shared/                    # JSON specs & schemas (not code)
│   ├── model-catalogue.json   # Model definitions across providers
│   ├── tool-schemas/          # JSON Schema for each built-in tool
│   ├── system-prompt.txt      # Default system prompt
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

## Extensions

pi-mobile supports an extension system for adding custom tools beyond the 7 built-ins. Extensions can:

- Register new tools with JSON Schema definitions
- Hook into the tool execution lifecycle
- Intercept tool calls with `ToolCallDecision` (Allow / Block / Modify)
- Be defined declaratively via JSON or programmatically

See `pi-extensions` (Android) or `PiExtensions` (iOS) for the extension interface and registry.

## Using as a Library

The individual modules can be consumed independently in your own apps.

### iOS (Swift Package Manager)

```swift
.package(url: "https://github.com/scgopi/pi-mobile", from: "1.0.0")
```

Then add the specific product targets you need (e.g., `PiAI`, `PiAgentCore`, `PiTools`).

### Android (Maven Central)

```kotlin
implementation("io.github.scgopi:pi-ai:1.0.0")
implementation("io.github.scgopi:pi-agent-core:1.0.0")
implementation("io.github.scgopi:pi-tools:1.0.0")
```

## Links

- [Contributing](CONTRIBUTING.md)
- [License](LICENSE) (Apache 2.0)
