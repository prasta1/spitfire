# Spitfire (reins-swift)

## Project Overview

Native iOS/macOS Ollama + OpenRouter chat client — clean-room Swift reimplementation of reins.

## Tech Stack

- SwiftUI
- SwiftData (persistence)
- iOS 17.0+ / macOS 14.0+
- XcodeGen (`project.yml` is source of truth — `Spitfire.xcodeproj` is generated, not checked in)

## Build

```sh
xcodegen generate
open Spitfire.xcodeproj
```

xcodegen binary: `/opt/homebrew/Cellar/xcodegen/2.45.4/bin/xcodegen`

## Project Layout

```
Spitfire/
  Configuration/        # AppState (ObservableObject), PlatformHelpers (iOS-only guards)
  Models/               # Domain types: OllamaMessage, OllamaChat, OllamaModel, OpenRouterModel
  Persistence/          # SwiftData @Models: ChatRecord, MessageRecord, FolderRecord
  Services/             # OllamaClient, OpenRouterClient (async/await + streaming NDJSON)
  ViewModels/           # ChatDetailViewModel (drives streaming + SwiftData writes)
  Views/                # All SwiftUI views
SpitfireTests/          # Unit tests (Testing framework)
project.yml             # XcodeGen spec
```

## Key Architecture Notes

- **Dual backend**: `OllamaClient` (local/self-hosted) and `OpenRouterClient` (cloud). Backend chosen per-chat at creation in `NewChatSheet`.
- **Streaming**: Both clients use `URLSession` bytes async sequences, parsing NDJSON line-by-line.
- **SwiftData quirks**: See `ISSUES.md` items 1–4. Key workarounds:
  - `OllamaChatOptions` is flattened to scalar fields on `ChatRecord` (not stored as Codable struct)
  - Message roles stored as `roleRaw: String`, exposed via computed `role` property
  - Backing storage must be `internal` (not `private`) for SwiftData schema visibility
- **iOS navigation**: Uses `NavigationStack` + `.navigationDestination(item:)` — NOT `NavigationSplitView`. The split view caused a persistent black-gap layout bug on iPhone (root cause: `UILaunchStoryboardName` missing from Info.plist confused initial window sizing).
- **macOS menubar extra**: `MenuBarExtra` in `SpitfireApp.swift`, popover in `MenuBarQuickQueryView.swift`. Custom template-rendered icon from `MenuBarIcon` asset (requires transparent background — white bg makes it invisible in dark mode).
- **Platform guards**: All iOS-only APIs wrapped in `#if os(iOS)` blocks, centralized in `PlatformHelpers.swift`.
- **OpenRouter API key**: Currently stored in `UserDefaults` (wiped on reinstall). Keychain migration planned.

## Key Files

| File | Purpose |
|------|---------|
| `Spitfire/SpitfireApp.swift` | App entry point, SwiftData container, MenuBarExtra |
| `Spitfire/Configuration/AppState.swift` | Shared app state (server URL, provider, API key) |
| `Spitfire/ContentView.swift` | Root view — NavigationSplitView (macOS) / NavigationStack (iOS) |
| `Spitfire/Services/OllamaClient.swift` | Ollama REST + streaming client |
| `Spitfire/Services/OpenRouterClient.swift` | OpenRouter REST + streaming client |
| `Spitfire/ViewModels/ChatDetailViewModel.swift` | Send/stream/persist message flow |
| `Spitfire/Views/NewChatSheet.swift` | New chat creation — backend + model picker |
| `Spitfire/Views/SettingsView.swift` | Settings — server URL, OpenRouter key, appearance |
| `Spitfire/Views/ChatDetailView.swift` | Chat thread view, export menu, context menus |
| `Spitfire/Views/MenuBarQuickQueryView.swift` | macOS menubar popover (macOS only) |
| `Spitfire/Persistence/ChatRecord.swift` | SwiftData chat model, transcript export helpers |
| `Spitfire/Persistence/MessageRecord.swift` | SwiftData message model, `plainContent` helper |
| `Spitfire/Info.plist` | App plist — must include `UILaunchStoryboardName` for correct iOS window sizing |

## Notes

- Independent codebase from reins-fork
- Per-conversation model/configuration support
- Privacy-first (local data; OpenRouter calls go to openrouter.ai only)
- After any Swift file changes, verify the build before moving on
