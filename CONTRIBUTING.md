# Contributing to pi-mobile

Thank you for your interest in contributing to pi-mobile! This guide covers development setup, code style, and the process for submitting changes.

## Development Environment

### iOS

- **Xcode 15.4+** with Swift 6.0+
- iOS 17+ deployment target
- Open the package you want to work on (e.g., `ios/PiAI/`) directly in Xcode, or open the `ios/` workspace

### Android

- **Android Studio** (latest stable)
- **JDK 17**
- Android 8.0+ (API 26) minimum SDK
- Open the `android/` directory as a Gradle project

## Code Style

### Swift

- Use **structured concurrency**: `Sendable`, `async/await`, `AsyncThrowingStream`
- Prefer value types (`struct`, `enum`) over reference types where practical
- Follow Swift API Design Guidelines for naming

### Kotlin

- Use **coroutines** (`suspend`, `Flow`) for async operations
- Use **kotlinx.serialization** for all JSON encoding/decoding
- Follow Kotlin coding conventions

## Adding a New Tool

Tools are defined in `pi-tools` (Android) / `PiTools` (iOS).

1. **Define the JSON Schema** — Add a schema file to `shared/tool-schemas/your_tool.json` describing the tool's parameters
2. **Implement the Tool protocol/interface:**
   - **iOS:** Create a new Swift file in `ios/PiTools/Sources/PiTools/` implementing the `Tool` protocol. Provide `name`, `description`, `parametersSchema`, and the `execute` method.
   - **Android:** Create a new Kotlin file in `android/pi-tools/src/main/kotlin/com/pimobile/tools/` implementing the `Tool` interface. Provide the same members.
3. **Register in BuiltInTools** — Add your tool to the built-in tools list so it's available to the agent loop
4. **Write tests** — Add unit tests covering the tool's core behavior

## Adding a New LLM Provider

Providers are handled in `pi-ai` (Android) / `PiAI` (iOS) via protocol adapters.

1. **Identify the wire protocol** — Determine which of the 4 supported protocols (openai-completions, openai-responses, anthropic, google) the provider uses
2. **If the provider uses an existing protocol** — Add the provider's base URL and any quirks to the appropriate adapter
3. **If the provider uses a new protocol:**
   - **iOS:** Create a new `ProtocolAdapter` implementation in `ios/PiAI/Sources/PiAI/`
   - **Android:** Create a new `ProtocolAdapter` implementation in `android/pi-ai/src/main/kotlin/com/pimobile/ai/`
4. **Update the model catalogue** — Add model entries to `shared/model-catalogue.json`
5. **Write tests** — Add unit tests for request/response serialization and streaming

## Testing

### iOS

```bash
cd ios && swift test
```

Individual packages can be tested directly:

```bash
cd ios/PiAI && swift test
cd ios/PiAgentCore && swift test
```

### Android

```bash
cd android && ./gradlew test
```

Individual modules:

```bash
cd android && ./gradlew :pi-ai:test
cd android && ./gradlew :pi-agent-core:test
```

## Pull Request Process

1. **Fork** the repository and create a feature branch from `main`
2. **Make your changes** following the code style guidelines above
3. **Write tests** for new functionality and ensure all existing tests pass
4. **Commit** with clear, descriptive commit messages
5. **Submit a PR** against `main` with:
   - A description of what changed and why
   - Links to any relevant issues
   - Screenshots for UI changes
6. **Address review feedback** — maintainers may request changes before merging

## Questions?

Open a GitHub issue for bugs or feature requests. For general discussion, use GitHub Discussions.
