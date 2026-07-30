import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:agent_ui_kit_providers/agent_ui_kit_providers.dart';
import 'package:agent_ui_kit_providers/providers.dart';
import 'package:flutter/material.dart';

import 'main.dart' show GlassBackdrop;

/// Which provider the form is currently configured for.
enum _ProviderKind {
  openRouter('OpenRouter', 'openai/gpt-4o'),
  gemini('Gemini', 'gemini-1.5-flash');

  const _ProviderKind(this.label, this.defaultModel);

  final String label;
  final String defaultModel;
}

/// Which built-in theme the live chat page is currently using. Local to this
/// page rather than shared with `main.dart`'s `DemoTheme` -- this page is a
/// standalone manual-test harness, so it carries its own tiny copy of the
/// light/dark/glass cycle instead of reaching back into the app shell.
enum _LiveTheme {
  light,
  dark,
  glass;

  AgentThemeData get data => switch (this) {
        _LiveTheme.light => AgentThemeData.light(),
        _LiveTheme.dark => AgentThemeData.dark(),
        _LiveTheme.glass => AgentThemeData.glass(),
      };

  IconData get icon => switch (this) {
        _LiveTheme.light => Icons.light_mode_rounded,
        _LiveTheme.dark => Icons.dark_mode_rounded,
        _LiveTheme.glass => Icons.blur_on_rounded,
      };
}

/// A minimal OpenAI-shaped tool schema for a fake `get_weather` function,
/// passed to [OpenRouterProvider.tools] so the model can actually call it.
const _weatherToolOpenAi = [
  {
    'type': 'function',
    'function': {
      'name': 'get_weather',
      'description': 'Get the current weather for a city.',
      'parameters': {
        'type': 'object',
        'properties': {
          'city': {
            'type': 'string',
            'description': 'The city to get the weather for.',
          },
        },
        'required': ['city'],
      },
    },
  },
];

/// The same tool, in Gemini's `functionDeclarations` shape.
const _weatherToolGemini = [
  {
    'name': 'get_weather',
    'description': 'Get the current weather for a city.',
    'parameters': {
      'type': 'object',
      'properties': {
        'city': {
          'type': 'string',
          'description': 'The city to get the weather for.',
        },
      },
      'required': ['city'],
    },
  },
];

/// Lets you paste a real API key and model id at runtime and chat against
/// [OpenRouterProvider] or [GeminiProvider] for real.
///
/// The key is held only in this form's own [TextEditingController] -- never
/// hardcoded, logged or persisted -- matching the kit's "host app owns the
/// key" design (see the README's Providers section).
class ProviderDemoPage extends StatefulWidget {
  const ProviderDemoPage({super.key});

  @override
  State<ProviderDemoPage> createState() => _ProviderDemoPageState();
}

class _ProviderDemoPageState extends State<ProviderDemoPage> {
  _ProviderKind _kind = _ProviderKind.openRouter;
  final _apiKeyController = TextEditingController();
  late final _modelController = TextEditingController(text: _kind.defaultModel);
  bool _enableTool = false;
  bool _simulateCitations = false;

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  void _selectKind(_ProviderKind kind) {
    if (kind == _kind) return;
    setState(() {
      _kind = kind;
      _modelController.text = kind.defaultModel;
    });
  }

  void _start() {
    final apiKey = _apiKeyController.text.trim();
    final model = _modelController.text.trim();
    if (apiKey.isEmpty || model.isEmpty) return;

    final AgentProvider provider = switch (_kind) {
      _ProviderKind.openRouter => OpenRouterProvider(
          apiKey: apiKey,
          model: model,
          tools: _enableTool ? _weatherToolOpenAi : null,
        ),
      _ProviderKind.gemini => GeminiProvider(
          apiKey: apiKey,
          model: model,
          functionDeclarations: _enableTool ? _weatherToolGemini : null,
        ),
    };

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _LiveProviderChatPage(
          provider: provider,
          toolEnabled: _enableTool,
          simulateCitations: _simulateCitations,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Live provider demo')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(theme.spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Paste a real API key to chat against an actual model. '
                'The key is used only for this session and is never saved.',
                style: theme.typography.bodySmall
                    .copyWith(color: theme.colors.textSecondary),
              ),
              SizedBox(height: theme.spacing.lg),
              SegmentedButton<_ProviderKind>(
                segments: [
                  for (final kind in _ProviderKind.values)
                    ButtonSegment(value: kind, label: Text(kind.label)),
                ],
                selected: {_kind},
                onSelectionChanged: (selection) => _selectKind(selection.first),
              ),
              SizedBox(height: theme.spacing.lg),
              TextField(
                controller: _apiKeyController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'API key',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: theme.spacing.md),
              TextField(
                controller: _modelController,
                decoration: const InputDecoration(
                  labelText: 'Model id',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: theme.spacing.lg),
              Text(
                'Also test',
                style: theme.typography.label
                    .copyWith(color: theme.colors.textSecondary),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _enableTool,
                onChanged: (v) => setState(() => _enableTool = v ?? false),
                title: const Text('Send a demo tool (get_weather)'),
                subtitle: const Text(
                  'Lets the model actually call a tool -- ask about the '
                  'weather somewhere to see the full pending → running → '
                  'success flow.',
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _simulateCitations,
                onChanged: (v) =>
                    setState(() => _simulateCitations = v ?? false),
                title: const Text('Simulate citations after each reply'),
                subtitle: const Text(
                  'Neither provider returns citations for real -- this '
                  'attaches fake ones so the citation UI is reachable too.',
                ),
              ),
              SizedBox(height: theme.spacing.lg),
              FilledButton(
                onPressed: _start,
                child: const Text('Start chat'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveProviderChatPage extends StatefulWidget {
  const _LiveProviderChatPage({
    required this.provider,
    required this.toolEnabled,
    required this.simulateCitations,
  });

  final AgentProvider provider;
  final bool toolEnabled;
  final bool simulateCitations;

  @override
  State<_LiveProviderChatPage> createState() => _LiveProviderChatPageState();
}

class _LiveProviderChatPageState extends State<_LiveProviderChatPage> {
  // A responder stays attached so ChatScreen's built-in regenerate/retry/
  // edit-and-resend affordances keep working (they call
  // ChatController.retryLast()/editMessage() internally, which require one).
  // The primary send path below overrides this with a hand-driven _streamTurn
  // so fresh turns surface tool calls, forward attachments, and can continue
  // the same message across tool-call rounds -- retry/edit fall back to this
  // plain text-only responder, which is an acceptable trade-off for a
  // manual-test harness.
  late final ChatController _chat = ChatController(
    responder: widget.provider.asResponder(history: () => _chat.messages),
  );
  late final ConversationController _conversations =
      ConversationController(chat: _chat);

  _LiveTheme _theme = _LiveTheme.light;

  List<Attachment> _attachments = [];

  final _random = Random();

  // Safety net against a model that keeps calling tools indefinitely --
  // each round is a real network turn, so this bounds the cost, not just the
  // loop.
  static const _maxToolRounds = 4;

  @override
  void dispose() {
    _conversations.dispose();
    widget.provider.dispose();
    super.dispose();
  }

  void _cycleTheme() {
    setState(() {
      _theme = _LiveTheme.values[(_theme.index + 1) % _LiveTheme.values.length];
    });
  }

  void _addTestImage() {
    setState(() {
      _attachments = [
        ..._attachments,
        Attachment(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: 'test-image.png',
          mimeType: 'image/png',
          kind: AttachmentKind.image,
          url: 'https://placehold.co/600x400.png',
        ),
      ];
    });
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachments = [..._attachments]..removeAt(index);
    });
  }

  Future<void> _send(String text) async {
    final attachments = _attachments;
    setState(() => _attachments = const []);
    final userMessage = ChatMessage.user(text, attachments: attachments);
    _chat.addMessage(userMessage);
    final assistantId = _chat.beginAssistantMessage();

    await _streamTurn(assistantId, round: 0);

    if (mounted && widget.simulateCitations) _attachSimulatedCitations();
  }

  void _attachSimulatedCitations() {
    final last = _chat.lastMessage;
    if (last == null || last.role != ChatRole.assistant) return;
    _chat.setCitations(last.id, [
      const Citation(
        id: 'c1',
        title: 'OpenWeatherMap weather',
        url: 'https://openweathermap.org',
      ),
      const Citation(
        id: 'c2',
        title: 'Open-Meteo weather',
        url: 'https://open-meteo.com/',
      ),
    ]);
  }

  /// Streams one assistant turn into [assistantId] and, if the model called
  /// a tool, resolves it and recurses into the next turn on the **same**
  /// message -- so a whole tool-calling exchange (tool call, then the real
  /// answer) renders as one bubble with one action row/response time once it
  /// truly finishes, rather than the tool-call stub reaching
  /// [MessageStatus.sent] (and showing its own actions) on its own partway
  /// through.
  ///
  /// This is what [AgentProvider.sendMessage] does internally for a single
  /// turn, extended with the round/continuation loop it doesn't support
  /// (there's no public "continue this turn" method to call instead).
  Future<void> _streamTurn(String assistantId, {required int round}) async {
    final conversation = _chat.messages;

    try {
      await for (final event in widget.provider.streamEvents(conversation)) {
        if (_chat.streamingMessageId != assistantId) return; // stopped
        switch (event) {
          case TextDelta(text: final chunk):
            _chat.appendToken(assistantId, chunk);
          case ToolCallEvent(:final call):
            _chat.upsertToolCall(assistantId, call);
        }
      }
    } catch (error) {
      if (_chat.streamingMessageId == assistantId) {
        _chat.failMessage(assistantId, error.toString());
      }
      return;
    }

    if (!mounted || _chat.streamingMessageId != assistantId) return; // stopped

    final pending = (_chat.messageById(assistantId)?.toolCalls ?? const [])
        .where((c) => c.status == ToolCallStatus.pending)
        .toList();

    if (!widget.toolEnabled || pending.isEmpty || round >= _maxToolRounds) {
      _chat.completeMessage(assistantId);
      return;
    }

    for (final call in pending) {
      await _resolveToolCall(assistantId, call);
      if (_chat.streamingMessageId != assistantId) return; // stopped mid-tool
    }

    await _streamTurn(assistantId, round: round + 1);
  }

  Future<void> _resolveToolCall(String assistantId, ToolCall call) async {
    _chat.upsertToolCall(
      assistantId,
      call.copyWith(status: ToolCallStatus.running, startedAt: DateTime.now()),
    );

    await Future<void>.delayed(const Duration(milliseconds: 700));

    // stop() clears streamingMessageId and marks any unfinished tool call
    // cancelled in the same call, so this one check covers both "the page
    // was stopped" and "this specific call was cancelled".
    if (!mounted || _chat.streamingMessageId != assistantId) return;

    _chat.upsertToolCall(
      assistantId,
      call.copyWith(
        status: ToolCallStatus.success,
        output: _fakeWeather(call.input),
        completedAt: DateTime.now(),
      ),
    );
  }

  String _fakeWeather(String? input) {
    var city = 'the requested location';
    if (input != null) {
      try {
        final decoded = jsonDecode(input);
        if (decoded is Map && decoded['city'] is String) {
          city = decoded['city'] as String;
        }
      } catch (_) {
        // Malformed input from the model -- fall back to the generic label.
      }
    }
    const conditions = ['Sunny', 'Partly cloudy', 'Light rain', 'Clear skies'];
    return jsonEncode({
      'city': city,
      'tempC': 18 + _random.nextInt(12),
      'condition': conditions[_random.nextInt(conditions.length)],
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final isGlass = _theme == _LiveTheme.glass;

    return AnimatedAgentTheme(
      data: _theme.data,
      child: ChatScreen(
        controller: _chat,
        conversations: _conversations,
        title: 'Live: ${widget.provider.runtimeType}',
        emptyTitle: 'Ask a real model',
        emptySubtitle: widget.toolEnabled
            ? 'Connected for real. Try the weather question below to see a '
                'live tool call; citations are ${widget.simulateCitations ? "simulated" : "off"}.'
            : 'Connected for real -- this calls out over the network. '
                'Citations are ${widget.simulateCitations ? "simulated" : "off"}.',
        suggestions: [
          if (widget.toolEnabled)
            const Suggestion(
              "What's the weather in Colombo?",
              icon: Icons.cloud_outlined,
            ),
          const Suggestion('Show me a markdown table',
              icon: Icons.table_chart_outlined),
          const Suggestion('Give me a Python code example',
              icon: Icons.code_rounded),
        ],
        followUps: const [
          Suggestion('Go deeper'),
          Suggestion('Give an example'),
          Suggestion('Summarize that'),
        ],
        onSend: (text) => unawaited(_send(text)),
        showTimestamps: true,
        showResponseTime: true,
        showActions: true,
        showAvatars: true,
        allowEditing: true,
        onAttach: _addTestImage,
        onRemoveAttachment: _removeAttachment,
        attachments: _attachments,
        onVoice: () => _snack('Wire this to speech_to_text'),
        onLinkTap: (url) => _snack('Open $url'),
        onFeedback: (message, feedback) =>
            _snack('Recorded ${feedback.name} feedback'),
        background: isGlass ? const GlassBackdrop() : null,
        historyDrawerBuilder: (context, conversations) => ChatHistoryDrawer(
          showSearch: true,
          searchThreshold: 0,
          controller: conversations,
          onSelected: () => Navigator.of(context).maybePop(),
        ),
        appBarActions: [
          IconButton(
            tooltip: 'Theme: ${_theme.name}',
            icon: Icon(_theme.icon),
            onPressed: _cycleTheme,
          ),
        ],
      ),
    );
  }
}
