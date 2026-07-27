# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`agent_ui_kit_providers` (formerly `agent_ui_kit`) is a Flutter package (intended for pub.dev) of
production-ready widgets for AI chat/agent interfaces: streaming markdown bubbles, tool-call visualization,
a themeable composer, and optional OpenRouter/Gemini provider integrations.

**The UI layer has no dependency of its own** — markdown parsing, syntax highlighting, and state management
under `lib/src/widgets/`, `lib/src/theme/`, `lib/src/markdown/`, and `lib/src/controllers/` are all
implemented in-house. `lib/src/providers/` is the one place allowed to depend on `http`, for the optional
OpenRouter/Gemini integrations exported separately from `lib/providers.dart` (see Layout below). Dart/pub
has no notion of an optional dependency, so `http` is resolved for every consumer regardless of which
library they import — but it should never leak into the UI-only code paths. Any *new* dependency beyond
`http` still needs a strong reason; don't add one to `pubspec.yaml` casually.

## Commands

```bash
flutter test                 # run the full test suite
flutter test test/foo_test.dart          # run a single test file
flutter test --plain-name "some test name"  # run a single test by name
flutter analyze              # static analysis — must be clean before committing
cd example && flutter run    # run the showcase app (streaming demo, widget gallery, theme switcher)
cd example && flutter test   # run the example app's own widget test
```

There is no build step for the package itself (it's a library, not an app) — `flutter analyze` and
`flutter test` are the CI gates. Both are expected to be clean on `main`.

## Do not publish or run on device

Never run `pub publish` or `flutter pub publish` (including `--dry-run`) — this requires explicit user
approval regardless of how the task is phrased. Likewise, never run `flutter run` or otherwise launch the
example app on a device/emulator — the maintainer tests on a physical device and owns that step personally.
Validate changes with `flutter analyze`/`flutter test` instead.

## Architecture

### Layout

- `lib/agent_ui_kit_providers.dart` — the main public entry point (renamed from `agent_ui_kit.dart`).
  Every UI-facing exported symbol is re-exported here from `lib/src/`; nothing under `lib/src/` should be
  imported directly by consumers. When adding a new public widget/model/controller, add its export here
  too. This library has no dependency of its own — do not add a `providers` export to it.
- `lib/providers.dart` — the second, opt-in entry point for model-provider integrations. Importing it (in
  addition to, or separately from, the main library above) pulls in `http`. New providers get added to
  `lib/src/providers/` and exported from here, never from `agent_ui_kit_providers.dart`.
- `lib/src/controllers/` — `ChangeNotifier`-based state (see below).
- `lib/src/models/` — immutable data classes (`ChatMessage`, `ToolCall`, `Conversation`, `Attachment`,
  `Citation`) with `copyWith`.
- `lib/src/markdown/` — a hand-rolled, streaming-aware markdown parser/AST/renderer/highlighter.
- `lib/src/theme/` — the token-based theming system.
- `lib/src/widgets/` — everything visual, built on top of the above.
- `lib/src/providers/` — `AgentProvider` base class plus `OpenRouterProvider`/`GeminiProvider` (see
  "Provider architecture" below). The only directory permitted to import `package:http`.
- `example/` — a runnable showcase app (`example/lib/main.dart`, `gallery_page.dart`, `fake_agent.dart`
  for simulated streaming).

### Controller-driven state

`ChatController` (`lib/src/controllers/chat_controller.dart`) is the core of the runtime model. It supports
two usage styles:

- **Managed**: construct with an `AgentResponder` (`Stream<String> Function(ChatMessage)`) and call
  `send()` — the controller appends a user message, opens a streaming assistant message, and pipes the
  stream into it via `appendToken`/`completeMessage`/`failMessage`.
- **Manual**: call `beginAssistantMessage()`, then `appendToken`/`upsertToolCall`/`setCitations` directly,
  then `completeMessage()`. Use this when a response interleaves text with tool calls, since a plain
  `Stream<String>` can't represent that.

Key invariants to preserve when touching this file:
- All mutation methods notify listeners only when something actually changed, and `_safeNotify()` guards
  against calling `notifyListeners()` after `dispose()` (stream callbacks can outlive the widget).
- `stop()` cancels the subscription but keeps partial text, and marks any unfinished tool calls
  `cancelled` rather than deleting them.
- `editMessage()` truncates everything after the edited message before regenerating — a reply to old
  wording is treated as no longer part of a coherent thread. This is a deliberate product decision, not
  an implementation detail; don't "fix" it to preserve trailing messages.

`ConversationController` (`lib/src/controllers/conversation_controller.dart`) wraps a single
`ChatController` and manages *which* conversation is loaded into it. It does not hold parallel message
lists per conversation at runtime — switching threads calls `chat.clear()` then `chat.addMessages(...)` on
the same controller, and a listener (`_syncActive`) mirrors the live controller's state back into the
stored `Conversation`. If you add new `ChatController` state that needs to persist across thread switches,
it must flow through this sync path or it will be lost on `select()`.

Persistence is intentionally out of scope — the package ships no database/storage. Host apps listen to
`ConversationController` and persist `conversations.conversations` themselves.

### Streaming-first markdown

`MarkdownView` (`lib/src/markdown/markdown_view.dart`) is built around the fact that its `data` string
grows token-by-token during a live response. The parser caches its previous result and, when new text is
a strict append to the old text, **re-parses only the trailing block** instead of the whole document —
this is what keeps rebuild cost linear instead of quadratic across a streamed reply. Any change to
`markdown_parser.dart` must preserve this incremental-append behavior; check
`test/markdown_streaming_test.dart` for the contract being tested. This is also why `flutter_markdown` was
dropped as a dependency (see README "Why not `flutter_markdown`?").

Selection is scoped per-message (`ChatBubble`/`MessageList`), not one `SelectionArea` wrapping the whole
list — wrapping the full scrolling list causes a framework crash once a reply outgrows the viewport. Keep
new selectable text inside per-message boundaries.

### Theming

`AgentThemeData` (`lib/src/theme/agent_theme.dart`) composes token groups — `AgentColors`,
`AgentTypography`, `AgentSpacing`, `AgentRadii`, `AgentMotion` — rather than exposing flat properties.
Three built-in variants: `.light()`, `.dark()`, `.glass()` (translucent, for gradient/image backdrops).
`AgentThemeData.fromTheme(Theme.of(context))` derives a theme from the host app's Material theme, and this
is the automatic fallback (`AgentTheme.of`) when no `AgentTheme` ancestor exists — widgets must not assume
an explicit `AgentTheme` is always present.

When adding a new theme token: add it to the relevant token group class (not directly on
`AgentThemeData`), update `copyWith`, `lerp` (used by `AnimatedAgentTheme`), `==`/`hashCode`, and the
`light`/`dark`/`glass`/`fromTheme` factories.

Read animation durations via `AgentTheme.motionOf(context)`, not `AgentTheme.of(context).motion` directly
— `motionOf` collapses to `AgentMotion.none` when the platform requests reduced motion, and bypassing it
breaks that accessibility path.

### Provider architecture

`AgentProvider` (`lib/src/providers/agent_provider.dart`) is the base class `OpenRouterProvider` and
`GeminiProvider` extend. It exposes two ways to drive a `ChatController`, mirroring the controller's own
managed/manual split:

- `asResponder({history})` adapts a provider to `AgentResponder` for `ChatController`'s managed `send()`.
  It strips empty assistant messages from `history()` before use — `ChatController.send()` calls
  `beginAssistantMessage()` (which appends an *empty* streaming placeholder) *before* invoking the
  responder, so the raw history would otherwise end in that placeholder instead of the real user turn.
  Tool calls are dropped in this mode; a `Stream<String>` can't represent them.
- `sendMessage(controller, text)` drives the controller's manual API directly (`beginAssistantMessage` →
  `appendToken`/`upsertToolCall` → `completeMessage`/`failMessage`), so tool calls surface as real
  `ToolCall`s at `ToolCallStatus.pending`. It checks `controller.streamingMessageId` on every loop
  iteration so a `controller.stop()` call stops new tokens from landing — but it does **not** cancel the
  underlying HTTP request, since `ChatController` has no public hook for external cancellation. This is a
  known, deliberate limitation, not an oversight; don't assume `stop()` frees the socket.

Providers never execute tools or run an agentic loop — they surface what the model asked for, at
`pending`, and it's the host app's job (via `controller.upsertToolCall`) to run the tool and report a
result back. Don't "complete" this into an autonomous loop without it being an explicit, separate decision.

`OpenRouterProvider` and `GeminiProvider` both stream via Server-Sent Events (`lib/src/providers/sse_utils.dart`,
internal/unexported) but have genuinely different wire formats — see the doc comments on each for the
specifics (role names, where the API key goes, how tool/function calls are framed). Don't assume one's
shape generalizes to the other.

### Accessibility constraints worth knowing

- The composer's default control size (`ChatInputBar.controlSize`) is 38dp, deliberately below Material's
  48dp touch-target guidance, to read as a compact capsule. This is a known, documented trade-off, not a
  bug — don't silently "fix" it to 48; the field height and corner radius derive from `controlSize`, so
  raising it is an app-level opt-in.
- Links never self-launch (`MarkdownView.onLinkTap` / `ChatBubble`) — the kit takes no `url_launcher`
  dependency, consistent with keeping the UI layer free of dependencies.

## Lint posture

`analysis_options.yaml` enables `strict-casts`, `strict-inference`, and `strict-raw-types`, plus
`public_member_api_docs` as a warning — every public symbol should carry a doc comment, matching the
existing style (see any file under `lib/src/`). It also enables `unawaited_futures`, `close_sinks`,
`cancel_subscriptions`: controller code that opens `StreamSubscription`s must cancel them (see
`ChatController._cancelSubscription` / `dispose`).
