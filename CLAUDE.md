# Spitfire (reins-swift)

## Project Overview

Native iOS/macOS Ollama chat client — clean-room Swift reimplementation of reins.

## Tech Stack

- SwiftUI
- iOS 17.0+ / macOS 14.0+
- XcodeGen (project.yml is source of truth)

## Build

```sh
xcodegen generate
open Spitfire.xcodeproj
```

## Project Layout

```
Spitfire/           # app sources
SpitfireTests/      # unit tests
project.yml         # xcodegen spec
```

## Notes

- Independent codebase from reins-fork
- Per-conversation model/configuration support
- Privacy-first (local data)
