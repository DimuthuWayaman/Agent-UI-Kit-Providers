import 'package:agent_ui_kit_providers/agent_ui_kit_providers.dart';
import 'package:flutter/material.dart';

/// A stand-in for a real model client.
///
/// Emits tokens on a timer so the demo exercises the same streaming path a
/// live provider would, including a mid-response pause where a tool call
/// would run.
class FakeAgent {
  const FakeAgent._();

  /// Starters shown in the empty state.
  static const List<Suggestion> starters = [
    Suggestion('Explain streaming', icon: Icons.bolt_outlined),
    Suggestion('Show me a table', icon: Icons.table_chart_outlined),
    Suggestion('Write some code', icon: Icons.code_rounded),
  ];

  /// Follow-ups offered above the composer once a conversation starts.
  static const List<Suggestion> followUps = [
    Suggestion('Go deeper'),
    Suggestion('Give an example'),
    Suggestion('Summarize that'),
  ];

  /// Streams a canned reply chosen from the prompt.
  static Stream<String> respond(ChatMessage message) async* {
    final reply = _replyFor(message.text.toLowerCase());

    // Chunk by word rather than character: closer to how real providers
    // deliver tokens, and it keeps the markdown parser honest about
    // partially-formed syntax.
    final words = reply.split(' ');
    for (var i = 0; i < words.length; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 28));
      yield i == 0 ? words[i] : ' ${words[i]}';
    }
  }

  static String _replyFor(String prompt) {
    if (prompt.contains('table')) return _tableReply;
    if (prompt.contains('code') || prompt.contains('write')) return _codeReply;
    return _defaultReply;
  }

  static const String _defaultReply = '''
Streaming works by appending tokens to a message as they arrive, and
re-rendering the markdown each time.

The naive approach re-parses the **entire** document on every token, which is
`O(n²)` across a response. This kit caches the parse and only re-parses the
tail, so it stays linear.

Things that keep working mid-stream:

- Unterminated code fences render as code immediately
- A half-typed `-` becomes a list item when the space arrives
- Auto-scroll follows along — *unless* you scroll up to read

> Scroll up during a reply and the view stops following you.

See the [docs](https://flutter.dev) for more.
''';

  static const String _codeReply = '''
Here is the whole integration:

```dart
final controller = ChatController(
  responder: (message) => client.streamReply(message.text),
);

ChatScreen(
  controller: controller,
  title: 'Assistant',
);
```

The same thing in Python, to show highlighting across languages:

```python
async def stream_reply(prompt: str):
    # Yields chunks as the model produces them.
    async for chunk in client.stream(prompt):
        yield chunk.text
```

That is the entire surface area for a working chat.
''';

  static const String _tableReply = '''
### Rendering support

| Feature | Streaming-safe | Notes |
|---|:---:|---|
| Headings | yes | ATX and setext |
| Code fences | yes | Renders before the closing fence |
| Tables | yes | Rows append as they arrive |
| Task lists | yes | `- [x]` and `- [ ]` |

Task list, live:

- [x] Parse incrementally
- [x] Highlight code
- [ ] Ship it
''';
}
