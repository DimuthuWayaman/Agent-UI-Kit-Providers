import 'package:agent_ui_kit_providers/agent_ui_kit_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'fake_agent.dart';
import 'gallery_page.dart';
import 'provider_demo_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Without this, Android paints its own opaque bar behind the system
  // navigation area — outside the Flutter canvas, so no in-app background
  // (the glass gradient in particular) can ever cover it. Edge-to-edge lets
  // Flutter draw the full screen; the transparent nav/status bar colors set
  // per-theme below are what actually make that area show the app's content.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const DemoApp());
}

/// Which built-in theme the showcase is currently using.
enum DemoTheme {
  /// [AgentThemeData.light].
  light,

  /// [AgentThemeData.dark].
  dark,

  /// [AgentThemeData.glass], drawn over a gradient.
  glass,
}

class DemoApp extends StatefulWidget {
  const DemoApp({super.key});

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  DemoTheme _theme = DemoTheme.light;

  // The conversation controller owns the chat controller, so history, new
  // chat and the live thread all stay in sync. It lives here rather than on
  // the chat page so the conversation survives navigating back to the menu.
  late final ConversationController _conversations = ConversationController(
    chat: ChatController(responder: FakeAgent.respond),
  );

  AgentThemeData get _agentTheme => switch (_theme) {
        DemoTheme.light => AgentThemeData.light(),
        DemoTheme.dark => AgentThemeData.dark(),
        DemoTheme.glass => AgentThemeData.glass(),
      };

  void _cycleTheme() {
    setState(() {
      _theme = DemoTheme.values[(_theme.index + 1) % DemoTheme.values.length];
    });
  }

  @override
  void dispose() {
    _conversations.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final agentTheme = _agentTheme;
    final isDark = agentTheme.brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Transparent so the app's own background — the glass gradient in
      // particular — extends all the way to the physical screen edges
      // instead of the system bars painting over it.
      value: (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
      child: MaterialApp(
        title: 'agent_ui_kit_providers',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: agentTheme.brightness,
          colorScheme: ColorScheme.fromSeed(
            seedColor: agentTheme.colors.accent,
            brightness: agentTheme.brightness,
          ),
        ),
        // Cross-fades the whole token set rather than snapping between themes.
        home: AnimatedAgentTheme(
          data: agentTheme,
          child: MenuPage(
            theme: _theme,
            conversations: _conversations,
            onCycleTheme: _cycleTheme,
          ),
        ),
      ),
    );
  }
}

/// Landing page offering the two demos.
///
/// Each opens as its own full-screen route. An earlier version put them behind
/// a persistent bottom [NavigationBar], which permanently ate vertical space
/// from both — a chat surface in particular wants the whole screen.
class MenuPage extends StatelessWidget {
  /// The active demo theme.
  final DemoTheme theme;

  /// Shared conversation state, so chats persist across visits.
  final ConversationController conversations;

  /// Advances to the next demo theme.
  final VoidCallback onCycleTheme;

  const MenuPage({
    super.key,
    required this.theme,
    required this.conversations,
    required this.onCycleTheme,
  });

  IconData get _themeIcon => switch (theme) {
        DemoTheme.light => Icons.light_mode_rounded,
        DemoTheme.dark => Icons.dark_mode_rounded,
        DemoTheme.glass => Icons.blur_on_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final agentTheme = AgentTheme.of(context);
    final colors = agentTheme.colors;
    final isGlass = theme == DemoTheme.glass;

    // A scroll view, not a fixed Column relying on Spacer to make everything
    // fit: Spacer can shrink to zero but not below it, so once the fixed
    // content (three menu cards plus the header) exceeds the available
    // height on a smaller screen, a Spacer-based layout overflows instead of
    // adapting. Scrolling degrades gracefully regardless of screen size or
    // how many cards this menu grows to.
    final content = SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(agentTheme.spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Theme: ${theme.name}',
                icon: Icon(_themeIcon),
                color: colors.textSecondary,
                onPressed: onCycleTheme,
              ),
            ),
            SizedBox(height: agentTheme.spacing.xl),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: colors.accentSubtle,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 28,
                color: colors.accent,
              ),
            ),
            SizedBox(height: agentTheme.spacing.lg),
            Text(
              'agent_ui_kit_providers',
              textAlign: TextAlign.center,
              style: agentTheme.typography.heading1
                  .copyWith(color: colors.textPrimary),
            ),
            SizedBox(height: agentTheme.spacing.sm),
            Text(
              'Drop-in Flutter widgets for AI chat and agent interfaces.',
              textAlign: TextAlign.center,
              style: agentTheme.typography.bodySmall
                  .copyWith(color: colors.textSecondary),
            ),
            SizedBox(height: agentTheme.spacing.xl * 1.5),
            _MenuCard(
              icon: Icons.forum_rounded,
              title: 'Chat demo',
              subtitle:
                  'Streaming markdown, tool calls, editing and history.',
              onTap: () => _open(
                context,
                ChatDemoPage(theme: theme, conversations: conversations),
              ),
            ),
            SizedBox(height: agentTheme.spacing.md),
            _MenuCard(
              icon: Icons.widgets_rounded,
              title: 'Widget gallery',
              subtitle: 'Every widget in the kit, in the current theme.',
              onTap: () => _open(context, const GalleryPage()),
            ),
            SizedBox(height: agentTheme.spacing.md),
            _MenuCard(
              icon: Icons.cloud_outlined,
              title: 'Live provider demo',
              subtitle: 'Paste an OpenRouter or Gemini key and chat for real.',
              onTap: () => _open(context, const ProviderDemoPage()),
            ),
            SizedBox(height: agentTheme.spacing.xl),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: isGlass ? Colors.transparent : colors.surface,
      body: isGlass
          ? Stack(
              // Without this, the Stack sizes itself from `content` — and a
              // SingleChildScrollView shrink-wraps to its own intrinsic
              // height rather than filling the available space. On a menu
              // this short, that left the Stack (and the Positioned.fill
              // background inside it) ending right after the last card
              // instead of covering the full screen.
              fit: StackFit.expand,
              children: [
                const Positioned.fill(child: GlassBackdrop()),
                content,
              ],
            )
          : content,
    );
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);
    final colors = theme.colors;

    return Material(
      color: colors.surfaceContainer,
      borderRadius: theme.radii.largeRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(theme.spacing.lg),
          decoration: BoxDecoration(
            borderRadius: theme.radii.largeRadius,
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.accentSubtle,
                  borderRadius: theme.radii.mediumRadius,
                ),
                child: Icon(icon, size: 21, color: colors.accent),
              ),
              SizedBox(width: theme.spacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.typography.label
                          .copyWith(color: colors.textPrimary),
                    ),
                    SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.typography.caption
                          .copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The chat demo, opened full screen from [MenuPage].
class ChatDemoPage extends StatelessWidget {
  /// The active demo theme, used to decide whether to draw the glass backdrop.
  final DemoTheme theme;

  /// Shared conversation state.
  final ConversationController conversations;

  const ChatDemoPage({
    super.key,
    required this.theme,
    required this.conversations,
  });

  @override
  Widget build(BuildContext context) {
    return ChatScreen(
      controller: conversations.chat,
      conversations: conversations,
      title: 'Chat demo',
      emptySubtitle: 'A demo agent. Ask anything — it fakes a streamed reply '
          'with markdown, a tool call and citations.',
      suggestions: FakeAgent.starters,
      followUps: FakeAgent.followUps,
      showTimestamps: true,
      onAttach: () => _snack(context, 'Wire this to file_picker'),
      onVoice: () => _snack(context, 'Wire this to speech_to_text'),
      onLinkTap: (url) => _snack(context, 'Open $url'),
      onFeedback: (message, feedback) =>
          _snack(context, 'Recorded ${feedback.name} feedback'),
      background: theme == DemoTheme.glass ? const GlassBackdrop() : null,
      showAvatars: true,
      userAvatar: const CircleAvatar(
        backgroundColor: Colors.blue,
        child: Icon(Icons.person, color: Colors.white),
      )
    );
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }
}

/// The gradient the glass theme is designed to sit on top of.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1A1033),
            Color(0xFF2D1B4E),
            Color(0xFF0F2027),
          ],
        ),
      ),
    );
  }
}
