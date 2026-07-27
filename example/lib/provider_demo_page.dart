import 'package:agent_ui_kit_providers/agent_ui_kit_providers.dart';
import 'package:agent_ui_kit_providers/providers.dart';
import 'package:flutter/material.dart';

/// Which provider the form is currently configured for.
enum _ProviderKind {
  openRouter('OpenRouter', 'openai/gpt-4o'),
  gemini('Gemini', 'gemini-1.5-flash');

  const _ProviderKind(this.label, this.defaultModel);

  final String label;
  final String defaultModel;
}

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
  late final _modelController =
      TextEditingController(text: _kind.defaultModel);

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
      _ProviderKind.openRouter =>
        OpenRouterProvider(apiKey: apiKey, model: model),
      _ProviderKind.gemini => GeminiProvider(apiKey: apiKey, model: model),
    };

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _LiveProviderChatPage(provider: provider),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Live provider demo')),
      body: SafeArea(
        child: Padding(
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
  const _LiveProviderChatPage({required this.provider});

  final AgentProvider provider;

  @override
  State<_LiveProviderChatPage> createState() => _LiveProviderChatPageState();
}

class _LiveProviderChatPageState extends State<_LiveProviderChatPage> {
  late final ChatController _controller = ChatController(
    responder:
        widget.provider.asResponder(history: () => _controller.messages),
  );

  @override
  void dispose() {
    _controller.dispose();
    widget.provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChatScreen(
      controller: _controller,
      title: 'Live provider',
      emptySubtitle: 'Connected for real -- this calls out over the network.',
      showTimestamps: true,
      showAvatars: false,
    );
  }
}
