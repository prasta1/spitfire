# Rains (reins-swift)

## Project Overview

Native iOS Ollama chat client — clean-room Swift reimplementation of reins.

## Tech Stack

- SwiftUI
- iOS 17.0+
- XcodeGen (project.yml is source of truth)

## Build

```sh
xcodegen generate
open Rains.xcodeproj
```

## Project Layout

```
Rains/              # app sources
RainsTests/         # unit tests
project.yml         # xcodegen spec
```

## Notes

- Independent codebase from reins-fork
- Per-conversation model/configuration support
- Privacy-first (local data)