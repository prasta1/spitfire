# Spitfire

<p align="center">
  <img src="Spitfire/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="128" alt="Spitfire app icon" />
</p>

Native iOS/macOS Ollama chat client, written in SwiftUI.

Inspired by [ibrahimcetin/reins](https://github.com/ibrahimcetin/reins) (Flutter, GPL-3.0). Spitfire is a clean-room reimplementation in Swift — independent codebase, same general feature direction (chat with self-hosted LLMs, per-conversation configuration, privacy-first).

## Features

- **Streaming chat** with any Ollama model or OpenRouter cloud model
- **Dual backend** — Ollama (local/self-hosted) or OpenRouter (cloud), selected per-chat at creation time
- **Per-conversation configuration** — model, system prompt, temperature, top-p, context size, and more
- **Model capability badges** — visual indicators for vision, audio, tools, and thinking support
- **Generation stats** — tokens, tok/s, and total duration displayed per message
- **Image attachments** — attach photos to messages for vision-capable models
- **Auto-generated chat titles** from your first message
- **Custom model creation** — save system prompt + options as a new server-side model
- **Smart model filtering** — embedding-only models hidden from chat pickers; OpenRouter free-only toggle
- **VRAM management** — view loaded models with memory usage, unload on demand
- **Model pulling** — search the Ollama registry and pull new models with streaming progress
- **Chat folders** — organize conversations into named folders in the sidebar
- **Chat export** — share transcript, export as Markdown (.md) or plain text (.txt), copy per-message
- **macOS menubar extra** — quick-query popover accessible from the menu bar
- **macOS support** — native macOS target alongside iOS
- **Theming** — system, light, or dark appearance
- **Privacy-first** — all data stays on-device, talks only to your Ollama server or OpenRouter API

## Requirements

- iOS 17.0+ / macOS 14.0+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — `Spitfire.xcodeproj` is generated, not checked in
- A reachable [Ollama](https://ollama.com) server (local, LAN, or Tailscale) and/or an [OpenRouter](https://openrouter.ai) API key

## Getting started

```sh
xcodegen generate
open Spitfire.xcodeproj
```

Configure your Ollama server URL and/or OpenRouter API key in Settings. Backend (Ollama vs OpenRouter) is selected when creating each new chat.

## Project layout

```
Spitfire/               # app sources
  Configuration/        # AppState, environment, platform helpers
  Models/               # domain types (OllamaMessage, OllamaChat, etc.)
  Persistence/          # SwiftData models (ChatRecord, MessageRecord, FolderRecord)
  Services/             # OllamaClient, OpenRouterClient (HTTP + streaming)
  ViewModels/           # ChatDetailViewModel
  Views/                # SwiftUI views
SpitfireTests/          # unit tests
project.yml             # XcodeGen spec — source of truth for project structure
```

## Roadmap

- Markdown code block rendering (fenced blocks with monospace + background)
- Edit-and-restream earlier messages
- Multi-image attachments
- Vision-capability gating on the attach button
- OpenRouter API key in Keychain (currently UserDefaults)
- Codebase context access (grant Spitfire read/write access to a local directory for coding assistance)
