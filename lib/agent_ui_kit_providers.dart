/// Drop-in Flutter widgets for building AI chat and agent interfaces.
///
/// This library has no runtime dependencies of its own: markdown rendering,
/// syntax highlighting and conversation state are all implemented here.
/// Optional OpenRouter/Gemini provider integrations live in
/// `package:agent_ui_kit_providers/providers.dart`, which pulls in
/// `package:http` — importing this library alone does not.
///
/// Start with [ChatScreen] for a complete surface, or compose [MessageList],
/// [ChatBubble], [ToolCallCard] and [ChatInputBar] yourself. Style everything
/// through [AgentTheme].
library;

// Controllers
export 'src/controllers/chat_controller.dart';
export 'src/controllers/conversation_controller.dart';

// Markdown
export 'src/markdown/markdown_ast.dart';
export 'src/markdown/markdown_parser.dart';
export 'src/markdown/markdown_view.dart';
export 'src/markdown/syntax_highlighter.dart';

// Models
export 'src/models/attachment.dart';
export 'src/models/chat_message.dart';
export 'src/models/citation.dart';
export 'src/models/conversation.dart';
export 'src/models/tool_call.dart';

// Theme
export 'src/theme/agent_colors.dart';
export 'src/theme/agent_metrics.dart';
export 'src/theme/agent_theme.dart';
export 'src/theme/agent_typography.dart';

// Widgets
export 'src/widgets/agent_avatar.dart';
export 'src/widgets/attachment_preview.dart';
export 'src/widgets/chat_bubble.dart';
export 'src/widgets/chat_history_drawer.dart';
export 'src/widgets/chat_input_bar.dart';
export 'src/widgets/chat_screen.dart';
export 'src/widgets/citation_chip.dart';
export 'src/widgets/code_block.dart';
export 'src/widgets/empty_state.dart';
export 'src/widgets/message_actions.dart';
export 'src/widgets/message_editor.dart';
export 'src/widgets/message_list.dart';
export 'src/widgets/suggestion_chips.dart';
export 'src/widgets/tool_call_card.dart';
export 'src/widgets/typing_indicator.dart';
