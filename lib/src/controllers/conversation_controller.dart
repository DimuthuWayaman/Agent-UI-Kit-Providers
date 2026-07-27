import 'package:flutter/foundation.dart';

import '../models/conversation.dart';
import 'chat_controller.dart';

/// Manages a set of conversations and which one is live.
///
/// It wraps a single [ChatController]: the active thread's messages live in
/// that controller, and every change is mirrored back into the stored
/// [Conversation]. Switching threads swaps the controller's contents, so the
/// rest of the UI keeps talking to one controller and never has to care that
/// history exists.
///
/// ```dart
/// final conversations = ConversationController(
///   chat: ChatController(responder: myResponder),
/// );
///
/// conversations.newConversation();
/// conversations.select(someId);
/// ```
///
/// Storage is left to the host app. Pass [initialConversations] on startup and
/// listen for changes to persist [conversations] however you like.
class ConversationController extends ChangeNotifier {
  /// The controller driving the active thread.
  final ChatController chat;

  final List<Conversation> _conversations;
  String? _activeId;
  bool _disposed = false;

  /// Whether [chat] was created here and should be disposed with this object.
  final bool _ownsChat;

  ConversationController({
    ChatController? chat,
    List<Conversation>? initialConversations,
    String? activeId,
  })  : chat = chat ?? ChatController(),
        _ownsChat = chat == null,
        _conversations =
            List<Conversation>.from(initialConversations ?? const []) {
    _activeId = activeId ?? _conversations.firstOrNull?.id;

    if (_activeId == null) {
      // There must always be somewhere to file messages. Without an active
      // thread from the start, anything sent straight through [chat] — which
      // is exactly what ChatScreen does — would be dropped on the floor
      // instead of recorded in history.
      final initial = Conversation(id: _generateId());
      _conversations.add(initial);
      _activeId = initial.id;
    } else {
      final active = _byId(_activeId!);
      if (active != null) this.chat.addMessages(active.messages);
    }

    this.chat.addListener(_syncActive);
    // Capture anything the supplied controller already held.
    if (this.chat.messages.isNotEmpty) _syncActive();
  }

  /// All conversations, pinned first, then most recently updated.
  List<Conversation> get conversations {
    final sorted = List<Conversation>.from(_conversations)
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;

        final byUpdated = b.updatedAt.compareTo(a.updatedAt);
        if (byUpdated != 0) return byUpdated;

        // Threads touched within the same microsecond tie on updatedAt, and
        // a tie would leave them in insertion order — which can show a newer
        // thread below an older one. Fall back to creation order, then to the
        // id, whose counter suffix always breaks the last tie.
        final byCreated = b.createdAt.compareTo(a.createdAt);
        if (byCreated != 0) return byCreated;
        return b.id.compareTo(a.id);
      });
    return List.unmodifiable(sorted);
  }

  /// Id of the live conversation, or null when none has been started.
  String? get activeId => _activeId;

  /// The live conversation, or null.
  Conversation? get active =>
      _activeId == null ? null : _byId(_activeId!);

  /// Whether there are no conversations at all.
  bool get isEmpty => _conversations.isEmpty;

  Conversation? _byId(String id) {
    final index = _conversations.indexWhere((c) => c.id == id);
    return index < 0 ? null : _conversations[index];
  }

  /// Mirrors the live controller's messages into the stored conversation.
  void _syncActive() {
    final id = _activeId;
    if (id == null) return;

    final index = _conversations.indexWhere((c) => c.id == id);
    if (index < 0) return;

    final existing = _conversations[index];
    final messages = chat.messages;

    _conversations[index] = existing.copyWith(
      messages: messages,
      // Only bump the timestamp when something actually arrived, so merely
      // opening a thread does not reorder the history list.
      updatedAt: messages.isEmpty ? existing.updatedAt : DateTime.now(),
    );
    _safeNotify();
  }

  /// Starts a new empty conversation and makes it active.
  ///
  /// Reuses the current thread when it is already empty rather than stacking
  /// up blank entries — tapping "new chat" twice should not create two.
  /// Returns the active conversation's id.
  String newConversation({String title = ''}) {
    final current = active;
    if (current != null && current.isEmpty && title.isEmpty) {
      return current.id;
    }

    final conversation = Conversation(id: _generateId(), title: title);
    _conversations.add(conversation);
    _activateInternal(conversation);
    return conversation.id;
  }

  /// Makes the conversation with [id] active, loading its messages.
  ///
  /// Does nothing if it is already active or does not exist.
  void select(String id) {
    if (id == _activeId) return;
    final conversation = _byId(id);
    if (conversation == null) return;
    _activateInternal(conversation);
  }

  void _activateInternal(Conversation conversation) {
    // Stop any in-flight response first: its chunks target a message in the
    // thread being navigated away from.
    chat
      ..stop()
      ..removeListener(_syncActive);

    _activeId = conversation.id;
    chat
      ..clear()
      ..addMessages(conversation.messages)
      ..addListener(_syncActive);

    _safeNotify();
  }

  /// Deletes the conversation with [id].
  ///
  /// When the active one is deleted, the next most recent becomes active, or
  /// a fresh empty conversation is started if none remain.
  void delete(String id) {
    final index = _conversations.indexWhere((c) => c.id == id);
    if (index < 0) return;

    _conversations.removeAt(index);

    if (_activeId != id) {
      _safeNotify();
      return;
    }

    final remaining = conversations;
    if (remaining.isEmpty) {
      _activeId = null;
      chat.clear();
      newConversation();
    } else {
      _activateInternal(remaining.first);
    }
  }

  /// Removes every conversation and starts a fresh one.
  void deleteAll() {
    _conversations.clear();
    _activeId = null;
    chat.clear();
    newConversation();
  }

  /// Sets an explicit title, overriding the one derived from the first
  /// message.
  void rename(String id, String title) {
    final index = _conversations.indexWhere((c) => c.id == id);
    if (index < 0) return;
    _conversations[index] = _conversations[index].copyWith(title: title);
    _safeNotify();
  }

  /// Pins or unpins a conversation, moving it to the top of the list.
  void setPinned(String id, bool pinned) {
    final index = _conversations.indexWhere((c) => c.id == id);
    if (index < 0) return;
    _conversations[index] = _conversations[index].copyWith(pinned: pinned);
    _safeNotify();
  }

  /// Conversations whose title or message text contains [query].
  ///
  /// Case-insensitive; an empty query returns everything.
  List<Conversation> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return conversations;

    return conversations.where((c) {
      if (c.displayTitle.toLowerCase().contains(q)) return true;
      return c.messages.any((m) => m.text.toLowerCase().contains(q));
    }).toList();
  }

  /// Sends [text] on the active thread, starting a conversation first if
  /// there is not one yet.
  Future<void> send(String text) async {
    if (_activeId == null) newConversation();
    await chat.send(text);
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    chat.removeListener(_syncActive);
    if (_ownsChat) chat.dispose();
    super.dispose();
  }
}

int _counter = 0;

String _generateId() {
  _counter++;
  return 'conv-${DateTime.now().microsecondsSinceEpoch}-$_counter';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Groups conversations into "Today", "Yesterday", and so on.
///
/// Used by the history list; exposed because apps often want the same
/// grouping in their own navigation.
Map<String, List<Conversation>> groupConversationsByDate(
  List<Conversation> conversations, {
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final startOfToday = DateTime(today.year, today.month, today.day);

  final groups = <String, List<Conversation>>{};
  for (final conversation in conversations) {
    final age = startOfToday.difference(
      DateTime(
        conversation.updatedAt.year,
        conversation.updatedAt.month,
        conversation.updatedAt.day,
      ),
    );

    final label = switch (age.inDays) {
      <= 0 => 'Today',
      1 => 'Yesterday',
      < 7 => 'Previous 7 days',
      < 30 => 'Previous 30 days',
      _ => 'Older',
    };

    groups.putIfAbsent(label, () => <Conversation>[]).add(conversation);
  }
  return groups;
}
