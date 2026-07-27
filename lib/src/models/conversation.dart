import 'package:flutter/foundation.dart';

import 'chat_message.dart';

/// One saved thread of messages.
///
/// Conversations are plain immutable data so they can be persisted with
/// whatever storage the host app already uses; the kit deliberately ships no
/// database of its own.
@immutable
class Conversation {
  /// Stable identifier.
  final String id;

  /// Display title. Derived from the first user message when not set
  /// explicitly — see [deriveTitle].
  final String title;

  /// The thread, oldest first.
  final List<ChatMessage> messages;

  /// When the conversation was started.
  final DateTime createdAt;

  /// When it last received a message.
  final DateTime updatedAt;

  /// Whether the user pinned it to the top of the history list.
  final bool pinned;

  /// Arbitrary caller data (model, system prompt, workspace id).
  final Map<String, Object?> metadata;

  Conversation({
    required this.id,
    this.title = '',
    List<ChatMessage>? messages,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.pinned = false,
    Map<String, Object?>? metadata,
  })  : messages = List.unmodifiable(messages ?? const <ChatMessage>[]),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now(),
        metadata = Map.unmodifiable(metadata ?? const <String, Object?>{});

  /// Whether the thread has no messages yet.
  bool get isEmpty => messages.isEmpty;

  /// The title to show in a history list.
  ///
  /// Falls back to the first user message, then to a placeholder, so an
  /// untitled thread never renders as a blank row.
  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    final derived = deriveTitle(messages);
    return derived.isEmpty ? 'New chat' : derived;
  }

  /// A one-line preview of the most recent message.
  String get preview {
    if (messages.isEmpty) return 'No messages yet';
    final last = messages.last;
    final text = last.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return '\u2026';
    return text.length <= 80 ? text : '${text.substring(0, 80)}\u2026';
  }

  /// Builds a title from the first user message, truncated on a word
  /// boundary so it does not cut mid-word.
  static String deriveTitle(List<ChatMessage> messages, {int maxLength = 40}) {
    final first = messages.where((m) => m.role == ChatRole.user).firstOrNull;
    if (first == null) return '';

    final text = first.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return '';
    if (text.length <= maxLength) return text;

    final cut = text.substring(0, maxLength);
    final lastSpace = cut.lastIndexOf(' ');
    return '${lastSpace > maxLength ~/ 2 ? cut.substring(0, lastSpace) : cut}\u2026';
  }

  Conversation copyWith({
    String? id,
    String? title,
    List<ChatMessage>? messages,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? pinned,
    Map<String, Object?>? metadata,
  }) {
    return Conversation(
      id: id ?? this.id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pinned: pinned ?? this.pinned,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Conversation &&
        other.id == id &&
        other.title == title &&
        listEquals(other.messages, messages) &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.pinned == pinned;
  }

  @override
  int get hashCode => Object.hash(
        id,
        title,
        Object.hashAll(messages),
        createdAt,
        updatedAt,
        pinned,
      );

  @override
  String toString() =>
      'Conversation($id, "$displayTitle", ${messages.length} messages)';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
