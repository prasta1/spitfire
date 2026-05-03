# Rains

Native iOS Ollama chat client, written in SwiftUI.

Inspired by [ibrahimcetin/reins](https://github.com/ibrahimcetin/reins) (Flutter, GPL-3.0). Rains is a clean-room reimplementation in Swift — independent codebase, new name, same general feature direction (chat with self-hosted LLMs, per-conversation configuration, privacy-first).

## Requirements

- iOS 17.0+
- Xcode 15+
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — `Rains.xcodeproj` is generated, not checked in
- A reachable [Ollama](https://ollama.com) server

## Getting started

```sh
xcodegen           # generate Rains.xcodeproj
open Rains.xcodeproj
```

## Project layout

```
Rains/                  # app sources
RainsTests/             # unit tests
project.yml             # xcodegen spec — source of truth for project structure
```
