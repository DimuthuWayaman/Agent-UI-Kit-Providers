/// Optional model-provider integrations (OpenRouter, Gemini) built on
/// `package:http`.
///
/// Importing this library — unlike
/// `package:agent_ui_kit_providers/agent_ui_kit_providers.dart` — pulls the
/// `http` dependency into your build. See the README's "Providers" section
/// for usage.
library;

export 'src/providers/agent_provider.dart';
export 'src/providers/gemini_provider.dart';
export 'src/providers/openrouter_provider.dart';
export 'src/providers/provider_event.dart';
