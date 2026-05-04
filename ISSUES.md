# Known issues / debt

Running list of things to revisit. Not bugs to ship — just stuff parked
while pushing through phases. Updated as items land or get superseded.

## SwiftData edge cases (workarounds in place, would be nice to revisit)

1. **Codable struct properties on `@Model` silently lose data.** `OllamaChatOptions`
   stored directly as a property roundtrips as defaults after fetch. Workaround:
   flattened to 13 scalar fields on `ChatRecord`, exposed via a computed
   `options` getter/setter. See `Spitfire/Persistence/ChatRecord.swift`.

2. **Raw-representable `String` enums on `@Model` crash silently.** `OllamaMessage.Role`
   stored directly causes the test process to crash without a stack frame.
   Workaround: store `roleRaw: String` and expose `role: OllamaMessage.Role` via
   a computed property. See `Spitfire/Persistence/MessageRecord.swift`.

3. **`@Model` skips `private` stored properties.** Initially marked the backing
   storage as `private`, which made it invisible to the schema and silently
   broke persistence. Have to be at least internal.

4. **`Data` properties on `@Model` also don't roundtrip reliably.** Tried
   storing `OllamaChatOptions` as `JSONEncoder().encode(...)` Data; same
   defaults-on-fetch behavior as #1. Hence the flatten approach.

## Untested / unverified

5. **No streaming-endpoint tests.** `URLProtocolStub` doesn't cleanly model
   chunked NDJSON delivery. Plan to smoke-test against a real Ollama server.

6. **No live UI smoke test.** Build is green and 33 unit tests pass, but I
   haven't actually run the simulator and clicked through send → stream →
   persist → relaunch. Needs human verification.

7. **OllamaClient in `ChatDetailViewModel` is captured at init.** If the user
   changes the server URL mid-conversation, in-progress chats keep the old
   client. Acceptable for now; revisit if it becomes a real annoyance.

## Polish gaps

8. **App icon is a 1024×1024 placeholder.** AppIcon.appiconset has no actual
   PNG. App will ship without an icon until art is added.

9. **Markdown rendering is inline-only.** Bold/italic/code/links work; full
   paragraph markdown (especially fenced code blocks with monospace + bg)
   doesn't. Would need a real renderer like swift-markdown-ui or a custom
   one — Apple's `AttributedString(markdown:)` only handles inline.

10. **No edit-message flow.** Regenerating the *last* assistant message
    via context menu is supported; editing earlier messages and re-streaming
    isn't.

11. **Single image per message only.** Schema is `imagesData: Data?`, not
    `[Data]`. Would need either repeated fields or a JSON-encoded array
    (which hits SwiftData issue #1 again, so probably a separate
    `MessageImage` `@Model` with relationship).

12. **No image compression.** PhotosPicker hands us full-resolution photos
    that get sent as-is to the server. Should resize/recompress before
    upload — Ollama vision models don't need 12MP input.

13. **No vision-capability gating in the input bar.** Attach button shows
    even for non-vision models. Server rejects with an error which we
    surface, but proactive UX would be better.

14. **Chat title is "New Chat" forever.** Flutter app has a generate-title
    flow (uses /api/generate with a fixed prompt). Not ported.

## Code Review - open code-minimax

Issues identified during code review. 2025-05-03.

### High Priority

**1. Naming Inconsistency**

- **Status**: **Resolved** — folder renamed to `Spitfire/`, all references updated.

**2. Unsafe Optionals & Silent Failures**

- **Location**: `Spitfire/Services/OllamaClient.swift:9`, `Spitfire/SpitfireApp.swift:10`
- **Observation**: Uses force-unwrap `URL(string: "http://localhost:11434")!` and `try!` for `ModelContainer`. These will crash at runtime if the string is ever malformed.
- **Risk**: High - No graceful degradation, app crashes on startup with malformed URL
- **Suggested Approach**:
  ```swift
  // In OllamaClient.swift, replace:
  init(baseURL: URL = URL(string: "http://localhost:11434")!, ...)
  // With:
  private static let defaultBaseURL = URL(string: "http://localhost:11434")!
  init(baseURL: URL? = nil, ...) {
      self.baseURL = baseURL ?? Self.defaultBaseURL  // safe fallback
  }
  ```
  For `SpitfireApp.swift`, wrap initialization in do-catch and show alert for user.
- **Related**: Overlaps with issue #8 (timeouts) - both involve network reliability.

### Medium Priority

**3. Missing Input Validation**

- **Location**: `Spitfire/Views/SettingsView.swift:98`
- **Observation**: URL validation only checks `scheme != nil`, doesn't validate format (e.g., `--` in hostname) or test reachability before saving.
- **Risk**: Medium - User can enter invalid URLs, no feedback until they try to chat
- **Suggested Approach**: Add URL validation in `commitURL()`:
  ```swift
  private func commitURL() {
      let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let url = URL(string: trimmed,
            let scheme = url.scheme,
            scheme != "http" && scheme != "https",
            url.host != nil else { return }  // invalid
      if url != appState.serverURL {
          appState.serverURL = url
          connectionState = .idle
      }
  }
  ```

**4. Potential Race Condition with Stream**

- **Location**: `Spitfire/ViewModels/ChatDetailViewModel.swift:56`, `Spitfire/Configuration/AppState.swift:36`
- **Observation**: Stream task captures `[client]` at init, but `AppState.serverURL` can replace the client object while streaming is in progress. In-flight requests use stale client.
- **Risk**: Medium - User changes URL mid-stream, previous stream keeps old client
- **Suggested Approach**: Make `OllamaClient` a class (reference type) instead of struct, so all callers share the same instance. Or pass a stable client ID and validate before processing responses.
- **Related**: See existing issue #7 - "OllamaClient in `ChatDetailViewModel` is captured at init" - same root cause, expand on that issue.

**5. listModels Performance**

- **Location**: `Spitfire/Services/OllamaClient.swift:113-137`
- **Observation**: `listModels()` calls `/api/show` sequentially for each model to fetch capabilities. With many models, this is slow.
- **Risk**: Medium - User experiences long load times when selecting model
- **Suggested Approach**: Use `withThrowingTaskGroup(of:)` to parallelize the `/api/show` calls:
  ```swift
  return try await withThrowingTaskGroup(of: (Int, OllamaModel).self) { group in
      for (index, tag) in tags.models.enumerated() {
          group.addTask {
              let capabilities = try? await self.showCapabilities(modelName: tag.name)
              // ... build model
          }
      }
      // collect results
  }
  ```

**6. Missing Accessibility Labels**

- **Location**: `Spitfire/Views/ChatDetailView.swift`, `Spitfire/Views/MessageBubbleView.swift`
- **Observation**: No `.accessibilityLabel()` or `.accessibilityHint()` on interactive elements. PhotosPicker attach button has no label.
- **Risk**: Medium - App not fully accessible via VoiceOver
- **Suggested Approach**: Add accessibility to key elements:
  ```swift
  PhotosPicker(..., label: { Text("Attach photo") })
      .accessibilityLabel("Attach photo to message")
  ```

**7. Network Timeouts Not Configured**

- **Location**: `Spitfire/Services/OllamaClient.swift:7`
- **Observation**: Uses `URLSession.shared` with default timeouts (60s). No custom configuration for slow/unreliable connections.
- **Risk**: Medium - Requests may timeout on large model cold-start or slow connections
- **Suggested Approach**: Create custom session with explicit timeouts:
  ```swift
  static let session: URLSession = {
      let config = URLSessionConfiguration.default
      config.timeoutIntervalForRequest = 120      // 2 min per request
      config.timeoutIntervalForResource = 300     // 5 min for streaming
      config.waitsForConnectivity = true
      return URLSession(configuration: config)
  }()
  ```
  Consider adding configurable timeouts via Settings for power users.

### Low Priority

**8. Verbose Options Storage**

- **Location**: `Spitfire/Persistence/ChatRecord.swift:23-35`
- **Observation**: Stores 12 `OllamaChatOptions` as flattened scalar properties. Verbose but ensures SwiftData reliability (see issue #1 above).
- **Risk**: Low - Works correctly, just verbose
- **Suggested Approach**: Keep current approach for iOS 17/18 compatibility. Future iOS versions may fix SwiftData Codable issues, revisit then.

---

**Summary**: 2 high, 5 medium, 1 low priority items. Items #2 (unsafe optionals) and #4 (race condition) should be addressed soonest as they can cause crashes.

## Done (struck through for history)

- ~~`createModel` / `deleteModel` Ollama endpoints.~~ Phase 5.
- ~~Image attachments in `MessageRecord`.~~ Phase 6.
- ~~Markdown rendering, edit/regenerate, app icon, accent color.~~
  Markdown (inline) + regenerate-last + accent color landed in Phase 7;
  app icon and full edit flow remain (#8, #10).
- ~~Splash screen with background image + logo.~~ Phase 8.

## Future / Proposed

15. **OpenRouter integration.** Add OpenRouter (cloud LLM models) as an
    alternative provider alongside Ollama (local models). Users can switch
    between providers in Settings.

    - **Approach**: Protocol-based `LLMService` with `OllamaClient` and
      `OpenRouterClient` implementations
    - **Storage**: API key in Keychain (not UserDefaults)
    - **Model list**: Fetch from OpenRouter API, filter to FREE models only
    - **Files affected**: 7 files (see detailed plan in project docs)
