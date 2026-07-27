import 'package:agent_ui_kit_providers/agent_ui_kit_providers.dart';
import 'package:flutter/material.dart';

/// Every widget in the kit, rendered in one scroll so theme changes can be
/// eyeballed across the whole surface at once.
///
/// Opened as its own full-screen route, so nothing competes with it for
/// vertical space.
class GalleryPage extends StatelessWidget {
  const GalleryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: theme.colors.surface,
      appBar: AppBar(
        title: const Text('Widget gallery'),
        backgroundColor: theme.colors.surface,
        foregroundColor: theme.colors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      // Deliberately no SelectionArea around this list: one placed above a
      // Scrollable crashes on drag-select as soon as a child outgrows the
      // viewport. The kit scopes selection per bubble for the same reason.
      body: ListView(
        padding: EdgeInsets.symmetric(vertical: theme.spacing.md),
        children: [
          _Section('Bubbles', [
            ChatBubble(
              message: ChatMessage.user('What is the weather in Colombo?'),
              showTimestamp: true,
            ),
            ChatBubble(
              message: ChatMessage.assistant(
                'It is **29°C** and partly cloudy.',
              ),
              avatar: const AgentAvatar(role: ChatRole.assistant),
              showTimestamp: true,
              showActions: true,
            ),
            ChatBubble(
              message: ChatMessage.system('Context window cleared'),
            ),
            ChatBubble(
              message: ChatMessage.assistant(
                'Partial answer that never fin',
                status: MessageStatus.failed,
              ).copyWith(error: 'Connection lost'),
              avatar: const AgentAvatar(role: ChatRole.assistant),
              onRetry: () {},
            ),
          ]),
          _Section('Grouping', [
            ChatBubble(
              message: ChatMessage.user('First in a run', id: 'g1'),
              groupPosition: BubbleGroupPosition.first,
            ),
            ChatBubble(
              message: ChatMessage.user('Middle', id: 'g2'),
              groupPosition: BubbleGroupPosition.middle,
            ),
            ChatBubble(
              message: ChatMessage.user('Last', id: 'g3'),
              groupPosition: BubbleGroupPosition.last,
              showTimestamp: true,
            ),
          ]),
          _Section('Thinking states', [
            const ThinkingBubble(
              label: 'Searching the web',
              avatar: AgentAvatar(role: ChatRole.assistant),
            ),
            ChatBubble(
              message: ChatMessage.assistant(
                'Tokens still arriving',
                status: MessageStatus.streaming,
              ),
              avatar: const AgentAvatar(role: ChatRole.assistant),
            ),
          ]),
          _Section('Tool calls', [
            ToolCallCard(
              toolCall: ToolCall(
                id: '1',
                name: 'get_weather',
                status: ToolCallStatus.success,
                input: '{\n  "city": "Colombo"\n}',
                output: '{\n  "tempC": 29,\n  "condition": "Partly cloudy"\n}',
                startedAt: now,
                completedAt: now.add(const Duration(milliseconds: 820)),
              ),
            ),
            const ToolCallCard(
              toolCall: ToolCall(
                id: '2',
                name: 'search_documents',
                status: ToolCallStatus.running,
                input: '{"query": "quarterly revenue"}',
              ),
            ),
            const ToolCallCard(
              toolCall: ToolCall(
                id: '3',
                name: 'send_email',
                status: ToolCallStatus.error,
                error: 'SMTP timeout after 30s',
              ),
            ),
            const ToolCallCard(
              toolCall: ToolCall(
                id: '4',
                name: 'cancelled_task',
                status: ToolCallStatus.cancelled,
              ),
            ),
          ]),
          _Section('Markdown', [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: theme.spacing.md),
              child: const MarkdownView(data: _markdownSample),
            ),
          ]),
          _Section('Code', [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: theme.spacing.md),
              child: const CodeBlock(
                code: 'void main() {\n'
                    '  // Entry point.\n'
                    '  const greeting = "hello";\n'
                    '  runApp(const MyApp(count: 42));\n'
                    '}',
                language: 'dart',
                showLineNumbers: true,
              ),
            ),
          ]),
          _Section('Citations', [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: theme.spacing.md),
              child: CitationList(
                citations: const [
                  Citation(
                    id: '1',
                    title: 'Flutter docs',
                    url: 'https://docs.flutter.dev/ui/widgets',
                    snippet: 'Widgets describe what their view should look '
                        'like given their configuration and state.',
                  ),
                  Citation(
                    id: '2',
                    title: 'Dart language tour',
                    url: 'https://dart.dev/language',
                  ),
                  Citation(id: '3', title: 'Internal design note'),
                ],
                onTap: (_) {},
              ),
            ),
          ]),
          _Section('Attachments', [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: theme.spacing.md),
              child: AttachmentPreviewList(
                attachments: [
                  Attachment(
                    id: '1',
                    name: 'quarterly-report.pdf',
                    sizeBytes: 2411724,
                  ),
                  Attachment(
                    id: '2',
                    name: 'notes.md',
                    sizeBytes: 4096,
                  ),
                  Attachment(
                    id: '3',
                    name: 'recording.mp3',
                    sizeBytes: 8912331,
                  ),
                ],
                onRemove: (_) {},
              ),
            ),
          ]),
          _Section('Suggestions', [
            SuggestionChips(
              suggestions: const [
                Suggestion('Summarize', icon: Icons.summarize_outlined),
                Suggestion('Translate', icon: Icons.translate_rounded),
                Suggestion('Explain', icon: Icons.help_outline_rounded),
              ],
              onSelected: (_) {},
            ),
          ]),
          _Section('Avatars', [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: theme.spacing.md),
              child: Row(
                children: [
                  const AgentAvatar(role: ChatRole.assistant),
                  SizedBox(width: theme.spacing.md),
                  const AgentAvatar(role: ChatRole.user, initials: 'Dimuthu W'),
                  SizedBox(width: theme.spacing.md),
                  const AgentAvatar(role: ChatRole.system),
                  SizedBox(width: theme.spacing.md),
                  AgentAvatar(
                    role: ChatRole.assistant,
                    size: 40,
                    statusColor: theme.colors.success,
                  ),
                ],
              ),
            ),
          ]),
          _Section('Composer', [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: theme.spacing.md),
              child: ChatInputBar(
                onSend: (_) {},
                onAttach: () {},
                onVoice: () {},
                maxLength: 120,
              ),
            ),
            SizedBox(height: theme.spacing.md),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: theme.spacing.md),
              child: ChatInputBar(
                onSend: (_) {},
                onStop: () {},
                isStreaming: true,
                hintText: 'Responding…',
              ),
            ),
          ]),
          SizedBox(height: theme.spacing.xl),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section(this.title, this.children);

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            theme.spacing.md,
            theme.spacing.xl,
            theme.spacing.md,
            theme.spacing.sm,
          ),
          child: Text(
            title.toUpperCase(),
            style: theme.typography.overline
                .copyWith(color: theme.colors.textTertiary),
          ),
        ),
        ...children,
      ],
    );
  }
}

const String _markdownSample = '''
# Heading one
## Heading two

Body text with **bold**, *italic*, ~~strikethrough~~ and `inline code`, plus a
[link](https://flutter.dev) and a bare URL https://dart.dev to autolink.

1. First ordered item
2. Second ordered item

- Bullet
  - Nested bullet
- [x] Completed task
- [ ] Pending task

> A blockquote, for quoting sources.

| Column | Value |
|---|---:|
| Latency | 820ms |
| Tokens | 1,204 |

---
''';
