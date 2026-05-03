# Known issues / debt

Running list of things to revisit once the core port is done. Not bugs to ship —
just stuff parked while pushing through phases.

## SwiftData edge cases (workarounds in place, would be nice to revisit)

1. **Codable struct properties on `@Model` silently lose data.** `OllamaChatOptions`
   stored directly as a property roundtrips as defaults after fetch. Workaround:
   flattened to 13 scalar fields on `ChatRecord`, exposed via a computed
   `options` getter/setter. See `Rains/Persistence/ChatRecord.swift`.

2. **Raw-representable `String` enums on `@Model` crash silently.** `OllamaMessage.Role`
   stored directly causes the test process to crash without a stack frame.
   Workaround: store `roleRaw: String` and expose `role: OllamaMessage.Role` via
   a computed property. See `Rains/Persistence/MessageRecord.swift`.

3. **`@Model` skips `private` stored properties.** Initially marked `optionsData`
   and `roleRaw` as `private`, which made them invisible to the schema and
   silently broke persistence. They have to be at least internal.

4. **`Data` properties on `@Model` also don't roundtrip reliably.** Tried
   storing `OllamaChatOptions` as `JSONEncoder().encode(...)` Data; same
   defaults-on-fetch behavior as #1. Hence the flatten approach.

## Untested / unverified

5. **No streaming-endpoint tests.** `URLProtocolStub` doesn't cleanly model
   chunked NDJSON delivery. Plan to smoke-test against a real Ollama server.

6. **No live UI smoke test.** Phase 3 builds clean and tests pass, but I
   haven't actually run the simulator and clicked through send → stream →
   persist → relaunch. Needs human verification.

7. **OllamaClient in `ChatDetailViewModel` is captured at init.** If the user
   changes the server URL mid-conversation, in-progress chats keep the old
   client. New chats pick up the new URL. Acceptable for now; revisit in
   Phase 7 polish.

## Deferred features

8. **`createModel` / `deleteModel` Ollama endpoints.** Not in the API client
   yet. Need a dynamic `parameters` dict that's awkward to encode in Swift.
   Plan: implement when Phase 5 wires up "save as custom model".

9. **Image attachments in `MessageRecord`.** Schema has `imagesData: Data?`
   placeholder but no encode/decode logic and no PhotosPicker integration.
   Phase 6.

10. **Markdown rendering, edit/regenerate, app icon.** All Phase 7 polish.
