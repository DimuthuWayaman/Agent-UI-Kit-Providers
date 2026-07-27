# Agent UI Kit Providers

[![pub package](https://img.shields.io/pub/v/agent_ui_kit_providers.svg)](https://pub.dev/packages/agent_ui_kit_providers)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Themeable Flutter widgets for AI chat and agent interfaces — streaming
markdown bubbles, tool-call visualization, a themeable composer, and optional
OpenRouter/Gemini provider integrations.

**The UI layer has no dependency of its own.** Only the optional provider
integrations (`package:agent_ui_kit_providers/providers.dart`) pull in
`http` — Dart/pub has no notion of an optional dependency, so it is resolved
for every consumer regardless of which library you import, but nothing under
`lib/src/widgets/`, `lib/src/theme/`, `lib/src/markdown/`, or
`lib/src/controllers/` needs it.

```yaml
dependencies:
  agent_ui_kit_providers: ^1.0.0
```

## Why

Every team wiring Claude, GPT, or Gemini into a Flutter app rebuilds the same
three things: a bubble that renders markdown while tokens stream in, a way to
show *what the model actually did* when it calls a tool, and a composer that
becomes a stop button mid-response. This package is all of that in one
themeable kit, so you can wire it up instead of rebuilding it.

## Contents

- [Sixty-second start](#sixty-second-start)
- [Composing it yourself](#composing-it-yourself)
- [Driving a response manually](#driving-a-response-manually)
- [Providers](#providers)
- [Conversations, new chat and history](#conversations-new-chat-and-history)
- [Editing a prompt](#editing-a-prompt)
- [What's included](#whats-included)
- [Theming](#theming)
- [Markdown](#markdown)
- [Accessibility](#accessibility)
- [Example](#example)

## Sixty-second start

```dart
import 'package:agent_ui_kit_providers/agent_ui_kit_providers.dart';

final controller = ChatController(
  responder: (message) => myClient.streamReply(message.text),
);

ChatScreen(
  controller: controller,
  title: 'Assistant',
  suggestions: const [
    Suggestion('Summarize a document', icon: Icons.description_outlined),
    Suggestion('Write a SQL query', icon: Icons.storage_outlined),
  ],
);
```

That gets you an empty state, streaming markdown, auto-scroll, copy/regenerate
actions, and a stop button. No theme setup required — the kit reads your app's
Material `ColorScheme` by default.

## Composing it yourself

`ChatScreen` is a convenience. Everything under it is public:

```dart
Column(
  children: [
    Expanded(
      child: MessageList(
        messages: controller.messages,
        showTimestamps: true,
        showActions: true,
        avatarBuilder: (context, m) => AgentAvatar(role: m.role),
        onLinkTap: (url) => launchUrlString(url),
      ),
    ),
    ChatInputBar(
      onSend: controller.send,
      onStop: controller.stop,
      isStreaming: controller.isStreaming,
    ),
  ],
)
```

## Driving a response manually

When a response interleaves text with tool calls, drive the controller
directly instead of handing it a single token stream:

```dart
final id = controller.beginAssistantMessage();

controller.appendToken(id, 'Let me check the weather.');

controller.upsertToolCall(id, ToolCall(
  id: 'call_1',
  name: 'get_weather',
  status: ToolCallStatus.running,
  input: '{"city": "Colombo"}',
  startedAt: DateTime.now(),
));

final result = await getWeather('Colombo');

controller.upsertToolCall(id, ToolCall(
  id: 'call_1',
  name: 'get_weather',
  status: ToolCallStatus.success,
  input: '{"city": "Colombo"}',
  output: result,
  startedAt: started,
  completedAt: DateTime.now(),
));

controller.appendToken(id, '\n\nIt is 29°C and partly cloudy.');
controller.completeMessage(id);
```

`controller.stop()` cancels the stream, keeps the partial text, and marks any
unfinished tool calls cancelled.

## Providers

`package:agent_ui_kit_providers/providers.dart` — a separate import from the
UI library above — ships `OpenRouterProvider` and `GeminiProvider`, so you can
wire a real model in without writing your own HTTP/SSE plumbing. Importing
this library pulls in the `http` package.

For plain text, `AgentProvider.asResponder` adapts a provider straight to
`ChatController`'s managed `send()`. Because the responder's closure needs to
read the controller's own message history, the controller has to be declared
`late final` so it can reference itself:

```dart
import 'package:agent_ui_kit_providers/agent_ui_kit_providers.dart';
import 'package:agent_ui_kit_providers/providers.dart';

final provider = OpenRouterProvider(
  apiKey: openRouterApiKey,
  model: 'anthropic/claude-sonnet-4.5', // or any OpenRouter-listed model
);

late final ChatController controller;
controller = ChatController(
  responder: provider.asResponder(history: () => controller.messages),
);

// Later:
provider.dispose();
```

When the model might call a tool, use `provider.sendMessage` instead of
`controller.send` — it drives the same manual API from "Driving a response
manually" above, so tool calls arrive as real `ToolCall`s rather than being
silently dropped from the text stream:

```dart
await provider.sendMessage(controller, 'What is the weather in Colombo?');

// The provider only reports what the model asked for, at ToolCallStatus.pending
// -- executing the tool and reporting the result back is your app's job, the
// same as in the manual-driving example above:
final result = await getWeather('Colombo');
controller.upsertToolCall(
  assistantMessageId,
  call.copyWith(status: ToolCallStatus.success, output: result),
);
```

`GeminiProvider` exposes the identical `asResponder`/`sendMessage` surface for
Google's native Gemini API:

```dart
final provider = GeminiProvider(
  apiKey: geminiApiKey,
  model: 'gemini-1.5-pro',
);
```

Both providers take API keys as plain strings — the kit stores nothing and
takes no dependency on secure storage, matching how conversation persistence
already works below: it is your app's job to source and hold the key.

## Conversations, new chat and history

Hand `ChatScreen` a `ConversationController` and it gains a history drawer, a
new-chat action, and thread switching:

```dart
final conversations = ConversationController(
  chat: ChatController(responder: myResponder),
  initialConversations: await loadFromStorage(),
);

ChatScreen(
  controller: conversations.chat,
  conversations: conversations,
  title: 'Assistant',
);
```

Threads are titled from their first user message, grouped by recency, and can
be renamed, pinned, deleted or searched. Persistence is yours — the kit ships
no database. Listen to the controller and save `conversations.conversations`
wherever you like.

## Editing a prompt

User messages carry an edit action. Rewriting one discards everything after it
and regenerates, because a reply to the old wording is no longer part of a
coherent thread. Turn it off with `allowEditing: false`, or drive it directly:

```dart
await controller.editMessage(messageId, 'the corrected prompt');
```

## What's included

| Widget | Purpose |
|---|---|
| `ChatScreen` | Complete chat surface — list, empty state, composer |
| `ChatHistoryDrawer` | Past conversations, search, rename, pin, delete |
| `MessageEditor` | Inline prompt editing |
| `MessageList` | Auto-scroll, message grouping, jump-to-latest |
| `ChatBubble` | Markdown, attachments, tool calls, citations, status |
| `ToolCallCard` | Collapsible tool call with status, timing and payloads |
| `ChatInputBar` | Auto-growing field, attachments, send/stop morph |
| `CodeBlock` | Syntax highlighting, language label, copy, collapse |
| `MarkdownView` | The streaming markdown renderer, usable standalone |
| `TypingIndicator` / `ThinkingBubble` | "Working on it" states |
| `CitationChip` / `CitationList` | Source attribution |
| `AttachmentPreview` | Image thumbnails and file chips |
| `SuggestionChips` | Starters and follow-ups |
| `ChatEmptyState` | Zero-state with starters |
| `AgentAvatar` | Role-aware avatars |
| `MessageActionBar` | Copy, regenerate, thumbs up/down |

## Theming

Themes are built from token groups — colors, typography, spacing, radii and
motion — so you restyle the whole kit in one place.

```dart
AgentTheme(
  data: AgentThemeData.dark(accent: Colors.tealAccent).copyWith(
    maxBubbleWidth: 720,
    radii: const AgentRadii(lg: 8),
  ),
  child: chatSurface,
)
```

Three variants ship built in: `AgentThemeData.light()`, `.dark()` and
`.glass()` (translucent, for gradient or image backdrops). `AgentThemeData
.fromTheme(Theme.of(context))` derives one from your app's Material theme —
which is what happens automatically if you never add an `AgentTheme` at all.

`AnimatedAgentTheme` cross-fades between themes instead of snapping:

```dart
AnimatedAgentTheme(
  data: isDark ? AgentThemeData.dark() : AgentThemeData.light(),
  child: chatSurface,
)
```

## Markdown

The renderer is built in and covers what models actually emit: headings,
**bold**, *italic*, ~~strikethrough~~, `inline code`, fenced code with syntax
highlighting, ordered/bulleted/task lists, tables, blockquotes, rules, links,
images and bare-URL autolinking.

It is built for streaming. The parse result is cached, and appending text
re-parses only the tail rather than the whole document — so rebuilding on every
token stays linear across a response instead of quadratic.

> **Why not `flutter_markdown`?** It was discontinued by the Flutter team, and
> it re-parses the entire document on every rebuild — which is exactly the hot
> path here. Dropping it also took the package to zero dependencies.

Links do not open themselves; the kit takes no `url_launcher` dependency.
Wire `onLinkTap` to whatever your app uses.

## Accessibility

- Semantics labels on every interactive element and message.
- Reduced-motion support throughout — animations collapse to zero duration
  when the platform requests it, and the typing indicator stops repainting.
- Text scales with the platform text scaler; `AgentTypography.scaled()` is
  available for an in-app size setting.
- Selection is scoped per message, which avoids the framework crash that a
  list-wide `SelectionArea` causes once a reply outgrows the viewport.

One deliberate trade-off: the composer's controls are 38dp, below Material's
48dp touch-target guidance, so the bar reads as a compact capsule. Raise
`ChatInputBar.controlSize` to 48 if you need the larger target — the field
height and corner radius derive from it, so the whole bar re-fits.

## Example

`example/` is a runnable showcase: streaming demo with tool calls, a widget
gallery, and a live theme switcher.

```bash
cd example
flutter run
```

## Contributing

Issues and PRs welcome. Run `flutter test` and `flutter analyze` before
submitting — both are clean on `main`.

## License

MIT — see [LICENSE](LICENSE).
