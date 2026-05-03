# Known issues / debt

Running list of things to revisit. Not bugs to ship — just stuff parked
while pushing through phases. Updated as items land or get superseded.

## SwiftData edge cases (workarounds in place, would be nice to revisit)

1. **Codable struct properties on `@Model` silently lose data.** `OllamaChatOptions`
   stored directly as a property roundtrips as defaults after fetch. Workaround:
   flattened to 13 scalar fields on `ChatRecord`, exposed via a computed
   `options` getter/setter. See `Rains/Persistence/ChatRecord.swift`.

2. **Raw-representable `String` enums on `@Model` crash silently.** `OllamaMessage.Role`
   stored directly causes the test process to crash without a stack frame.
   Workaround: store `roleRaw: String` and expose `role: OllamaMessage.Role` via
   a computed property. See `Rains/Persistence/MessageRecord.swift`.

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

## Done (struck through for history)

- ~~`createModel` / `deleteModel` Ollama endpoints.~~ Phase 5.
- ~~Image attachments in `MessageRecord`.~~ Phase 6.
- ~~Markdown rendering, edit/regenerate, app icon, accent color.~~
  Markdown (inline) + regenerate-last + accent color landed in Phase 7;
  app icon and full edit flow remain (#8, #10).
