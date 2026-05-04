# Spitfire

<p align="center">
  <img src="Spitfire/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="128" alt="Spitfire app icon" />
</p>

Native iOS/macOS Ollama chat client, written in SwiftUI.

Inspired by [ibrahimcetin/reins](https://github.com/ibrahimcetin/reins) (Flutter, GPL-3.0). Spitfire is a clean-room reimplementation in Swift — independent codebase, same general feature direction (chat with self-hosted LLMs, per-conversation configuration, privacy-first).

## Features

- **Streaming chat** with any Ollama model
- **Per-conversation configuration** — model, system prompt, temperature, top-p, context size, and more
- **Model capability badges** — visual indicators for vision, audio, tools, and thinking support
- **Generation stats** — tokens, tok/s, and total duration displayed per message
- **Image attachments** — attach photos to messages for vision-capable models
- **Auto-generated chat titles** from your first message
- **Custom model creation** — save system prompt + options as a new server-side model
- **Smart model filtering** — embedding-only models hidden from chat pickers
- **VRAM management** — view loaded models with memory usage, unload on demand
- **Model pulling** — search the Ollama registry and pull new models with streaming progress
- **macOS support** — native macOS target alongside iOS
- **Theming** — system, light, or dark appearance
- **Privacy-first** — all data stays on-device, talks only to your Ollama server

## Requirements

- iOS 17.0+ / macOS 14.0+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — `Spitfire.xcodeproj` is generated, not checked in
- A reachable [Ollama](https://ollama.com) server (local, LAN, or Tailscale)

## Getting started

```sh
xcodegen generate
open Spitfire.xcodeproj
```

Configure your Ollama server URL in Settings (defaults to `http://localhost:11434`).

## Project layout

```
Spitfire/               # app sources
  Configuration/        # AppState, environment
  Models/               # domain types (OllamaMessage, OllamaChat, etc.)
  Persistence/          # SwiftData models (ChatRecord, MessageRecord)
  Services/             # OllamaClient (HTTP + streaming)
  ViewModels/           # ChatDetailViewModel
  Views/                # SwiftUI views
SpitfireTests/          # unit tests
project.yml             # XcodeGen spec — source of truth for project structure
```

## Roadmap

- OpenRouter integration (cloud LLM provider alongside local Ollama)
- Markdown code block rendering
- Edit-and-restream earlier messages
- Multi-image attachments
- Vision-capability gating on the attach button

## License

Independent codebase. Not a fork of reins.
