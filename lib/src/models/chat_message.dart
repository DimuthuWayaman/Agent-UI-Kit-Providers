import 'package:flutter/foundation.dart';

import 'attachment.dart';
import 'citation.dart';
import 'tool_call.dart';

/// Sentinel default for a `copyWith` parameter, distinguishing "omitted" (use
/// the current value) from an explicit `null` (clear the field).
const Object _unset = Object();

/// Who authored a message.
enum ChatRole {
  /// The human using the app.
  user,

  /// The model.
  assistant,

  /// Out-of-band notices: context resets, safety messages, errors.
  system,
}

/// Delivery state of a message.
enum MessageStatus {
  /// Queued locally, not yet acknowledged by the backend.
  sending,

  /// Accepted by the backend.
  sent,

  /// Tokens are still arriving.
  streaming,

  /// Send or generation failed. [ChatMessage.error] carries the reason.
  failed,

  /// Generation was stopped by the user before it finished.
  ///
  /// Set by `ChatController.stop()`. Distinct from [failed] — nothing went
  /// wrong, the response was just cut short.
  stopped,
}

/// A single message in a conversation.
///
/// Immutable by design: streaming updates produce a new instance through
/// [copyWith] (or [appendText]) so widgets can rely on `==` for rebuild
/// decisions instead of mutating shared state.
@immutable
class ChatMessage {
  /// Stable identifier, unique within a conversation.
  final String id;

  /// Who authored this message.
  final ChatRole role;

  /// Message body. Rendered as markdown when
  /// [ChatMessage.isMarkdown] is true.
  final String text;

  /// Delivery state.
  final MessageStatus status;

  /// When the message was created.
  final DateTime createdAt;

  /// When the message stopped receiving updates — set when it leaves
  /// [MessageStatus.streaming], whether by finishing normally, being
  /// stopped, or failing. Null while streaming (or for a message that was
  /// never streamed at all).
  final DateTime? completedAt;

  /// Tool calls made while producing this message.
  final List<ToolCall> toolCalls;

  /// Files attached to this message.
  final List<Attachment> attachments;

  /// Sources referenced by this message.
  final List<Citation> citations;

  /// Failure reason when [status] is [MessageStatus.failed].
  final String? error;

  /// Whether [text] should be parsed as markdown.
  ///
  /// User messages usually should not be — a user typing `*` means an
  /// asterisk, not emphasis.
  final bool isMarkdown;

  /// Arbitrary caller data (model name, token usage, trace ids). Ignored by
  /// the kit; carried so you do not need a parallel map keyed by message id.
  final Map<String, Object?> metadata;

  ChatMessage({
    required this.id,
    required this.role,
    this.text = '',
    this.status = MessageStatus.sent,
    DateTime? createdAt,
    this.completedAt,
    List<ToolCall>? toolCalls,
    List<Attachment>? attachments,
    List<Citation>? citations,
    this.error,
    bool? isMarkdown,
    Map<String, Object?>? metadata,
  })  : createdAt = createdAt ?? DateTime.now(),
        toolCalls = List.unmodifiable(toolCalls ?? const <ToolCall>[]),
        attachments = List.unmodifiable(attachments ?? const <Attachment>[]),
        citations = List.unmodifiable(citations ?? const <Citation>[]),
        isMarkdown = isMarkdown ?? role != ChatRole.user,
        metadata = Map.unmodifiable(metadata ?? const <String, Object?>{});

  /// Creates a user message.
  factory ChatMessage.user(
    String text, {
    String? id,
    List<Attachment>? attachments,
    MessageStatus status = MessageStatus.sent,
  }) {
    return ChatMessage(
      id: id ?? _generateId(),
      role: ChatRole.user,
      text: text,
      status: status,
      attachments: attachments,
    );
  }

  /// Creates an assistant message.
  factory ChatMessage.assistant(
    String text, {
    String? id,
    MessageStatus status = MessageStatus.sent,
    List<ToolCall>? toolCalls,
    List<Citation>? citations,
  }) {
    return ChatMessage(
      id: id ?? _generateId(),
      role: ChatRole.assistant,
      text: text,
      status: status,
      toolCalls: toolCalls,
      citations: citations,
    );
  }

  /// Creates a system notice.
  factory ChatMessage.system(String text, {String? id}) {
    return ChatMessage(
      id: id ?? _generateId(),
      role: ChatRole.system,
      text: text,
    );
  }

  /// Whether tokens are still arriving for this message.
  bool get isStreaming => status == MessageStatus.streaming;

  /// Whether this message failed.
  bool get hasFailed => status == MessageStatus.failed;

  /// Whether generation was stopped by the user before it finished.
  bool get wasStopped => status == MessageStatus.stopped;

  /// How long generation took, from [createdAt] to [completedAt].
  ///
  /// Null while streaming, or for a message that never recorded a
  /// [completedAt] (e.g. one constructed directly with a terminal status).
  Duration? get responseTime => completedAt?.difference(createdAt);

  /// True when there is nothing to render yet — no text, no tools, no files.
  ///
  /// An assistant message in this state is waiting on its first token, which
  /// is when a standalone thinking indicator should be shown.
  bool get isEmpty =>
      text.trim().isEmpty && toolCalls.isEmpty && attachments.isEmpty;

  /// Returns a copy with [chunk] appended to [text].
  ///
  /// The common streaming operation, kept explicit so callers do not
  /// accidentally write `copyWith(text: chunk)` and drop prior tokens.
  ChatMessage appendText(String chunk) => copyWith(text: text + chunk);

  /// Returns a copy with the given fields replaced.
  ///
  /// [error] defaults to a sentinel rather than `null`, so omitting it
  /// preserves the current value while passing `null` explicitly clears it
  /// — e.g. `copyWith(status: MessageStatus.streaming, error: null)` clears a
  /// previous failure when regenerating in place.
  ChatMessage copyWith({
    String? id,
    ChatRole? role,
    String? text,
    MessageStatus? status,
    DateTime? createdAt,
    DateTime? completedAt,
    List<ToolCall>? toolCalls,
    List<Attachment>? attachments,
    List<Citation>? citations,
    Object? error = _unset,
    bool? isMarkdown,
    Map<String, Object?>? metadata,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      text: text ?? this.text,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      toolCalls: toolCalls ?? this.toolCalls,
      attachments: attachments ?? this.attachments,
      citations: citations ?? this.citations,
      error: identical(error, _unset) ? this.error : error as String?,
      isMarkdown: isMarkdown ?? this.isMarkdown,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Returns a copy with [call] inserted, replacing any existing tool call
  /// that shares its id.
  ChatMessage upsertToolCall(ToolCall call) {
    final next = List<ToolCall>.from(toolCalls);
    final index = next.indexWhere((c) => c.id == call.id);
    if (index >= 0) {
      next[index] = call;
    } else {
      next.add(call);
    }
    return copyWith(toolCalls: next);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatMessage &&
        other.id == id &&
        other.role == role &&
        other.text == text &&
        other.status == status &&
        other.createdAt == createdAt &&
        other.completedAt == completedAt &&
        listEquals(other.toolCalls, toolCalls) &&
        listEquals(other.attachments, attachments) &&
        listEquals(other.citations, citations) &&
        other.error == error &&
        other.isMarkdown == isMarkdown;
  }

  @override
  int get hashCode => Object.hash(
        id,
        role,
        text,
        status,
        createdAt,
        completedAt,
        Object.hashAll(toolCalls),
        Object.hashAll(attachments),
        Object.hashAll(citations),
        error,
        isMarkdown,
      );

  @override
  String toString() =>
      'ChatMessage($id, $role, ${text.length} chars, $status)';
}

int _idCounter = 0;

/// Monotonic, collision-free id for locally created messages.
///
/// Deliberately not a UUID: the kit takes no dependencies, and ids only need
/// to be unique within one app session. Supply your own [ChatMessage.id] when
/// persisting across sessions.
String _generateId() {
  _idCounter++;
  return '${DateTime.now().microsecondsSinceEpoch}-$_idCounter';
}
