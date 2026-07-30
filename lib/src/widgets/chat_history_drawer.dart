import 'package:flutter/material.dart';

import '../controllers/conversation_controller.dart';
import '../models/conversation.dart';
import '../theme/agent_theme.dart';

/// A navigation drawer listing past conversations, with a "new chat" action
/// and search.
///
/// Threads are grouped by recency (Today, Yesterday, Previous 7 days) because
/// a flat list of forty untitled chats is unnavigable, and pinned ones are
/// hoisted to the top.
class ChatHistoryDrawer extends StatefulWidget {
  /// The controller holding the conversations.
  final ConversationController controller;

  /// Header shown above the new-chat button.
  final String title;

  /// Whether to show the search field.
  ///
  /// Hidden automatically while there are only a handful of conversations.
  final bool showSearch;

  /// Conversation count above which search appears.
  final int searchThreshold;

  /// Called after a conversation is selected, typically to close the drawer.
  final VoidCallback? onSelected;

  /// Extra items pinned to the bottom, e.g. settings.
  final List<Widget> footerActions;

  const ChatHistoryDrawer({
    super.key,
    required this.controller,
    this.title = 'Chats',
    this.showSearch = true,
    this.searchThreshold = 6,
    this.onSelected,
    this.footerActions = const [],
  });

  @override
  State<ChatHistoryDrawer> createState() => _ChatHistoryDrawerState();
}

class _ChatHistoryDrawerState extends State<ChatHistoryDrawer> {
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _search.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(ChatHistoryDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _search.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _select(Conversation conversation) {
    widget.controller.select(conversation.id);
    widget.onSelected?.call();
  }

  void _startNew() {
    widget.controller.newConversation();
    widget.onSelected?.call();
  }

  Future<void> _confirmDelete(Conversation conversation) async {
    final theme = AgentTheme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete chat?'),
        content: Text(
          '"${conversation.displayTitle}" will be permanently removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: theme.colors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) widget.controller.delete(conversation.id);
  }

  Future<void> _rename(Conversation conversation) async {
    final controller =
        TextEditingController(text: conversation.displayTitle);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename chat'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    final title = result?.trim();
    if (title != null && title.isNotEmpty) {
      widget.controller.rename(conversation.id, title);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);
    final colors = theme.colors;

    final all = widget.controller.conversations;
    final visible = widget.controller.search(_search.text);
    final grouped = groupConversationsByDate(visible);
    final searchVisible =
        widget.showSearch && all.length > widget.searchThreshold;

    // Fixed order, so groups do not jump around as threads age.
    const order = [
      'Today',
      'Yesterday',
      'Previous 7 days',
      'Previous 30 days',
      'Older',
    ];

    return Drawer(
      backgroundColor: colors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                theme.spacing.lg,
                theme.spacing.lg,
                theme.spacing.lg,
                theme.spacing.sm,
              ),
              child: Text(
                widget.title,
                style: theme.typography.heading2
                    .copyWith(color: colors.textPrimary),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: theme.spacing.md),
              child: _NewChatButton(onPressed: _startNew),
            ),
            if (searchVisible)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  theme.spacing.md,
                  theme.spacing.md,
                  theme.spacing.md,
                  0,
                ),
                child: _SearchField(controller: _search),
              ),
            SizedBox(height: theme.spacing.sm),
            Expanded(
              child: visible.isEmpty
                  ? _EmptyHistory(searching: _search.text.trim().isNotEmpty)
                  : ListView(
                      padding: EdgeInsets.only(bottom: theme.spacing.lg),
                      children: [
                        for (final label in order)
                          if (grouped[label]?.isNotEmpty ?? false) ...[
                            _GroupHeader(label: label),
                            for (final conversation in grouped[label]!)
                              _ConversationTile(
                                conversation: conversation,
                                selected: conversation.id ==
                                    widget.controller.activeId,
                                onTap: () => _select(conversation),
                                onRename: () => _rename(conversation),
                                onDelete: () => _confirmDelete(conversation),
                                onTogglePin: () =>
                                    widget.controller.setPinned(
                                  conversation.id,
                                  !conversation.pinned,
                                ),
                              ),
                          ],
                      ],
                    ),
            ),
            if (widget.footerActions.isNotEmpty) ...[
              Divider(height: 1, color: colors.border),
              ...widget.footerActions,
            ],
          ],
        ),
      ),
    );
  }
}

class _NewChatButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _NewChatButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);
    final colors = theme.colors;

    return Material(
      color: colors.accentSubtle,
      borderRadius: theme.radii.mediumRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: theme.spacing.md,
            vertical: theme.spacing.md,
          ),
          child: Row(
            children: [
              Icon(Icons.add_rounded, size: 19, color: colors.accent),
              SizedBox(width: theme.spacing.sm),
              Text(
                'New chat',
                style: theme.typography.label.copyWith(color: colors.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;

  const _SearchField({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);
    final colors = theme.colors;

    return TextField(
      controller: controller,
      style: theme.typography.bodySmall.copyWith(color: colors.textPrimary),
      cursorColor: colors.accent,
      decoration: InputDecoration(
        hintText: 'Search chats',
        hintStyle:
            theme.typography.bodySmall.copyWith(color: colors.textTertiary),
        prefixIcon: Icon(Icons.search_rounded, size: 18, color: colors.textTertiary),
        prefixIconConstraints: const BoxConstraints(minWidth: 38),
        isDense: true,
        filled: true,
        fillColor: colors.surfaceContainer,
        contentPadding: EdgeInsets.symmetric(vertical: theme.spacing.sm),
        border: OutlineInputBorder(
          borderRadius: theme.radii.mediumRadius,
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: theme.radii.mediumRadius,
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: theme.radii.mediumRadius,
          borderSide: BorderSide(color: colors.accent),
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String label;

  const _GroupHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        theme.spacing.lg,
        theme.spacing.lg,
        theme.spacing.lg,
        theme.spacing.xs,
      ),
      child: Text(
        label.toUpperCase(),
        style: theme.typography.overline
            .copyWith(color: theme.colors.textTertiary),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;

  const _ConversationTile({
    required this.conversation,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onTogglePin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);
    final colors = theme.colors;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: theme.spacing.sm,
        vertical: 1,
      ),
      child: Material(
        color: selected ? colors.accentSubtle : Colors.transparent,
        borderRadius: theme.radii.smallRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: theme.spacing.md,
            ),
            child: Row(
              children: [
                if (conversation.pinned) ...[
                  Icon(
                    Icons.push_pin_rounded,
                    size: 13,
                    color: colors.textTertiary,
                  ),
                  SizedBox(width: theme.spacing.xs + 2),
                ],
                Expanded(
                  child: Text(
                    conversation.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.bodySmall.copyWith(
                      color: selected ? colors.accent : colors.textPrimary,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                _TileMenu(
                  pinned: conversation.pinned,
                  onRename: onRename,
                  onDelete: onDelete,
                  onTogglePin: onTogglePin,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TileMenu extends StatelessWidget {
  final bool pinned;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;

  const _TileMenu({
    required this.pinned,
    required this.onRename,
    required this.onDelete,
    required this.onTogglePin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);
    final colors = theme.colors;

    return PopupMenuButton<String>(
      tooltip: 'Chat options',
      icon: Icon(
        Icons.more_horiz_rounded,
        size: 17,
        color: colors.textTertiary,
      ),
      padding: EdgeInsets.zero,
      iconSize: 17,
      constraints: const BoxConstraints(minWidth: 160),
      color: colors.surfaceContainer,
      onSelected: (value) => switch (value) {
        'rename' => onRename(),
        'pin' => onTogglePin(),
        'delete' => onDelete(),
        _ => null,
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'rename',
          child: _MenuRow(
            icon: Icons.edit_outlined,
            label: 'Rename',
            color: colors.textPrimary,
          ),
        ),
        PopupMenuItem(
          value: 'pin',
          child: _MenuRow(
            icon: pinned
                ? Icons.push_pin_outlined
                : Icons.push_pin_rounded,
            label: pinned ? 'Unpin' : 'Pin',
            color: colors.textPrimary,
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: _MenuRow(
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            color: colors.error,
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MenuRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);

    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        SizedBox(width: theme.spacing.md),
        Text(label, style: theme.typography.bodySmall.copyWith(color: color)),
      ],
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  final bool searching;

  const _EmptyHistory({required this.searching});

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);

    return Center(
      child: Padding(
        padding: EdgeInsets.all(theme.spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching
                  ? Icons.search_off_rounded
                  : Icons.forum_outlined,
              size: 30,
              color: theme.colors.textTertiary,
            ),
            SizedBox(height: theme.spacing.md),
            Text(
              searching ? 'No matching chats' : 'No chats yet',
              textAlign: TextAlign.center,
              style: theme.typography.bodySmall
                  .copyWith(color: theme.colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
