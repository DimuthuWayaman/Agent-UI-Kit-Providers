# Changelog

All notable changes to this project are documented here. This project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.1.0

### Fixes

- **`ChatController`** — streams could keep delivering tokens after `stop()`, `removeMessage()` or
  `dispose()`; unfinished tool calls are now reliably marked cancelled and subscriptions torn down in all
  three paths.
- **`ConversationController`** — loading `initialConversations` whose messages already existed in the live
  `ChatController` could duplicate them; now guarded.
- **`ChatInputBar`** — guarded against double-submit, fixed the character counter not updating when
  `maxLength` is set, and attachments are now cleared via `onRemoveAttachment` on send.

### Features

- **Streaming-aware markdown** — `MarkdownView`/`MarkdownParser` gained an `isStreaming` flag that
  optimistically renders unclosed `**`/`_`/`~~`/`` ` `` spans and pending table headers while a reply is
  still arriving, instead of showing the raw markers until the closing token lands.
- **Response time and interrupted state** — `ChatBubble`/`MessageList` can show how long a reply took
  (`ChatMessage.responseTime`) and an "Interrupted" caption for messages ended by `stop()`
  (`ChatMessage.wasStopped`).
- **`GeminiProvider`** — added image attachment support (inline data and file-data parts).
- **`ChatScreen`** — added `showHistory` and `historyDrawerBuilder` to customize or suppress the history
  drawer.
- **`ChatMessage`/`ToolCall`** — `copyWith` now distinguishes an omitted argument from an explicit `null`,
  so `error`/`input`/`output` can be cleared intentionally.

### Docs

- README now includes screenshots and GIFs throughout (streaming reply, tool-call round trip, theme
  switching, widget gallery), and `pubspec.yaml` gained a `screenshots:` carousel entry for the pub.dev
  package page.

## 1.0.0

Initial release.

### Chat runtime

- **`ChatController`** — conversation state with streaming, cancellation, retry and tool-call
  bookkeeping. Supports a managed `send()` API backed by an `AgentResponder`, and a manual API
  (`beginAssistantMessage` / `appendToken` / `upsertToolCall` / `completeMessage`) for responses that
  interleave text with tool calls.
- **`ConversationController`** — manages which `Conversation` is loaded into a `ChatController`. New chat,
  switch threads, rename, pin, delete, and search across titles and message bodies, grouped by recency.
- **Prompt editing** — user messages can be rewritten in place via `MessageEditor`.
  `ChatController.editMessage` discards everything after the edited message and regenerates, since replies
  to the old wording no longer belong to the thread. Disable with `allowEditing: false`.
- **Models** — `ChatMessage`, `ToolCall`, `Attachment`, `Citation`, `Conversation`, with `copyWith`, value
  equality and status lifecycles.

### Widgets

- **`ChatScreen`** — a complete prebuilt chat surface. Pass `conversations:` and it gains a
  `ChatHistoryDrawer` and a new-chat action.
- **`MessageList`** — auto-scroll that stops following when the user scrolls up, message grouping, and a
  jump-to-latest button.
- **`ChatBubble`** — markdown body, attachments, tool calls, citations, status and actions (copy,
  regenerate, feedback, edit), laid out in a single row beneath the bubble.
- **`CodeBlock`** — syntax highlighting, language label, copy button, and collapsing for very long
  snippets.
- **`ChatInputBar`** — a themeable composer; every control shares `controlSize` so it stays a true capsule
  with no dead space around its icons.
- **`MarkdownView`** — headings, lists, task lists, tables, blockquotes, code, links, images and autolinks,
  built to stream: it caches its previous parse and re-parses only the trailing block on each append,
  keeping rebuild cost linear across a streamed reply.
- **`SyntaxHighlighter`** — Dart, JavaScript, TypeScript, Python, JSON, SQL and shell, with a sensible
  fallback for unknown languages.
- **More widgets** — `AgentAvatar`, `CitationChip`, `CitationList`, `AttachmentPreview`, `SuggestionChips`,
  `ChatEmptyState`, `MessageActionBar`, `ThinkingBubble`, `ChatHistoryDrawer`.

### Theming

- **Design tokens** — `AgentColors`, `AgentTypography`, `AgentSpacing`, `AgentRadii`, `AgentMotion`,
  composed into `AgentThemeData` with `light()`, `dark()`, `glass()` and `fromTheme()` variants.
- **`AnimatedAgentTheme`** — cross-fades between themes instead of snapping.
- Reduced-motion support throughout, via `AgentTheme.motionOf`. Semantics labels on every interactive
  element.

### Providers (`package:agent_ui_kit_providers/providers.dart`)

- **`OpenRouterProvider`** and **`GeminiProvider`** — stream a real model's replies straight into a
  `ChatController`. `asResponder()` adapts either to the managed `send()` API; `sendMessage()` drives the
  manual API so tool calls the model requests surface as real `ToolCall`s. Neither executes tools itself —
  reporting a result back is the host app's job via `controller.upsertToolCall`.
- `AgentProvider`, `ProviderEvent`/`TextDelta`/`ToolCallEvent`, `AgentProviderException` — the shared base
  types behind both providers.
- This is the only part of the package with a dependency of its own (`http`), imported separately from
  `lib/providers.dart`. The UI layer (widgets, theme, markdown, controllers, models) has none.
