import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/attachment.dart';
import '../models/chat_message.dart';
import '../models/citation.dart';
import '../models/tool_call.dart';

/// Signature for the function that turns a user message into assistant
/// output.
///
/// Yield text chunks as they arrive from your provider; the controller
/// appends each chunk to the in-flight assistant message.
typedef AgentResponder = Stream<String> Function(ChatMessage userMessage);

/// Holds conversation state and drives streaming updates.
///
/// Two usage styles are supported:
///
/// **Managed** — hand it a [responder] and call [send]:
///
/// ```dart
/// final controller = ChatController(
///   responder: (msg) => myClient.streamReply(msg.text),
/// );
/// controller.send('Hello');
/// ```
///
/// **Manual** — drive each step yourself, which is what you want when the
/// response interleaves tool calls with text:
///
/// ```dart
/// final id = controller.beginAssistantMessage();
/// controller.appendToken(id, 'Check');
/// controller.upsertToolCall(id, ToolCall(id: 't1', name: 'search'));
/// controller.completeMessage(id);
/// ```
///
/// Remember to [dispose] it — an in-flight stream is cancelled on disposal.
class ChatController extends ChangeNotifier {
  final List<ChatMessage> _messages;
  final AgentResponder? _responder;

  StreamSubscription<String>? _subscription;
  String? _streamingMessageId;
  bool _disposed = false;

  ChatController({
    List<ChatMessage>? initialMessages,
    AgentResponder? responder,
  })  : _messages = List<ChatMessage>.from(initialMessages ?? const []),
        _responder = responder;

  /// The conversation, oldest first. Unmodifiable — mutate through the
  /// controller's methods so listeners stay in sync.
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// Whether a response is currently streaming.
  bool get isStreaming => _streamingMessageId != null;

  /// The id of the message currently being streamed, if any.
  String? get streamingMessageId => _streamingMessageId;

  /// Whether the conversation has no messages.
  bool get isEmpty => _messages.isEmpty;

  /// The most recent message, or `null` when empty.
  ChatMessage? get lastMessage =>
      _messages.isEmpty ? null : _messages.last;

  /// Looks up a message by id, or `null` when absent.
  ChatMessage? messageById(String id) {
    final index = _messages.indexWhere((m) => m.id == id);
    return index < 0 ? null : _messages[index];
  }

  // ---------------------------------------------------------------------
  // Mutation
  // ---------------------------------------------------------------------

  /// Appends [message] to the conversation.
  void addMessage(ChatMessage message) {
    _messages.add(message);
    _safeNotify();
  }

  /// Appends several messages in one notification.
  void addMessages(Iterable<ChatMessage> messages) {
    _messages.addAll(messages);
    _safeNotify();
  }

  /// Replaces the message with [id] by applying [update] to it.
  ///
  /// Does nothing when no such message exists, so late-arriving stream events
  /// for a removed message are harmless.
  void updateMessage(String id, ChatMessage Function(ChatMessage) update) {
    final index = _messages.indexWhere((m) => m.id == id);
    if (index < 0) return;
    _messages[index] = update(_messages[index]);
    _safeNotify();
  }

  /// Removes the message with [id].
  void removeMessage(String id) {
    final removed = _messages.length;
    _messages.removeWhere((m) => m.id == id);
    if (_messages.length != removed) {
      if (_streamingMessageId == id) _cancelSubscription();
      _safeNotify();
    }
  }

  /// Clears the conversation and cancels any in-flight stream.
  void clear() {
    _cancelSubscription();
    _messages.clear();
    _safeNotify();
  }

  // ---------------------------------------------------------------------
  // Streaming primitives
  // ---------------------------------------------------------------------

  /// Adds an empty assistant message in the streaming state and returns its
  /// id, for use with [appendToken] and [completeMessage].
  String beginAssistantMessage({String? id}) {
    final message = ChatMessage(
      id: id ?? 'assistant-${DateTime.now().microsecondsSinceEpoch}',
      role: ChatRole.assistant,
      status: MessageStatus.streaming,
    );
    _messages.add(message);
    _streamingMessageId = message.id;
    _safeNotify();
    return message.id;
  }

  /// Appends a text chunk to the message with [id].
  void appendToken(String id, String chunk) {
    updateMessage(id, (m) => m.appendText(chunk));
  }

  /// Adds or replaces a tool call on the message with [id].
  void upsertToolCall(String id, ToolCall call) {
    updateMessage(id, (m) => m.upsertToolCall(call));
  }

  /// Attaches [citations] to the message with [id].
  void setCitations(String id, List<Citation> citations) {
    updateMessage(id, (m) => m.copyWith(citations: citations));
  }

  /// Marks the message with [id] as finished.
  void completeMessage(String id) {
    updateMessage(id, (m) => m.copyWith(status: MessageStatus.sent));
    if (_streamingMessageId == id) {
      _streamingMessageId = null;
      _subscription = null;
    }
    _safeNotify();
  }

  /// Marks the message with [id] as failed with [error].
  void failMessage(String id, String error) {
    updateMessage(
      id,
      (m) => m.copyWith(status: MessageStatus.failed, error: error),
    );
    if (_streamingMessageId == id) {
      _cancelSubscription();
    }
    _safeNotify();
  }

  // ---------------------------------------------------------------------
  // Managed send
  // ---------------------------------------------------------------------

  /// Adds a user message and streams a reply through the [AgentResponder]
  /// given to the constructor.
  ///
  /// Throws a [StateError] when no responder was supplied — use the manual
  /// primitives in that case. Ignored while a response is already streaming.
  Future<void> send(String text, {List<Attachment>? attachments}) async {
    final responder = _responder;
    if (responder == null) {
      throw StateError(
        'ChatController.send requires a responder. Either pass one to the '
        'constructor or drive streaming with beginAssistantMessage / '
        'appendToken / completeMessage.',
      );
    }
    if (isStreaming) return;
    if (text.trim().isEmpty && (attachments?.isEmpty ?? true)) return;

    final userMessage = ChatMessage.user(text, attachments: attachments);
    _messages.add(userMessage);
    final assistantId = beginAssistantMessage();

    await _consume(responder(userMessage), assistantId);
  }

  /// Streams [tokens] into a new assistant message.
  ///
  /// Use when you drive the request yourself but still want the controller to
  /// manage append/complete/error bookkeeping.
  Future<void> streamResponse(Stream<String> tokens) async {
    if (isStreaming) return;
    final assistantId = beginAssistantMessage();
    await _consume(tokens, assistantId);
  }

  Future<void> _consume(Stream<String> source, String assistantId) async {
    final completer = Completer<void>();

    _subscription = source.listen(
      (chunk) => appendToken(assistantId, chunk),
      onError: (Object error, StackTrace _) {
        failMessage(assistantId, error.toString());
        if (!completer.isCompleted) completer.complete();
      },
      onDone: () {
        // A stop() between the last chunk and onDone already finalized the
        // message; completing again would resurrect a cancelled stream.
        if (_streamingMessageId == assistantId) {
          completeMessage(assistantId);
        }
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    return completer.future;
  }

  /// Stops the in-flight response, keeping whatever text already arrived.
  ///
  /// This is what the input bar's stop button calls.
  void stop() {
    final id = _streamingMessageId;
    if (id == null) return;
    _cancelSubscription();
    updateMessage(id, (m) => m.copyWith(status: MessageStatus.sent));
    _markPendingToolCallsCancelled(id);
    _safeNotify();
  }

  /// Rewrites the user message with [id] and regenerates from that point.
  ///
  /// Everything after the edited message is discarded, because a reply to the
  /// old wording is no longer part of a coherent conversation. With a
  /// responder attached the new text is sent immediately; otherwise the text
  /// is updated and it is up to the caller to regenerate.
  ///
  /// Returns without doing anything while a response is streaming, or when
  /// [id] does not refer to a user message.
  Future<void> editMessage(String id, String newText) async {
    if (isStreaming) return;

    final index = _messages.indexWhere((m) => m.id == id);
    if (index < 0) return;

    final original = _messages[index];
    if (original.role != ChatRole.user) return;

    final trimmed = newText.trim();
    if (trimmed.isEmpty || trimmed == original.text) return;

    _messages.removeRange(index, _messages.length);
    _safeNotify();

    if (_responder == null) {
      _messages.add(original.copyWith(text: trimmed));
      _safeNotify();
      return;
    }

    await send(trimmed, attachments: original.attachments);
  }

  /// Removes the last assistant message and re-sends the user message before
  /// it. Requires a responder.
  Future<void> retryLast() async {
    if (isStreaming) return;
    final lastUserIndex = _messages.lastIndexWhere(
      (m) => m.role == ChatRole.user,
    );
    if (lastUserIndex < 0) return;

    final userMessage = _messages[lastUserIndex];
    _messages.removeRange(lastUserIndex, _messages.length);
    _safeNotify();

    await send(userMessage.text, attachments: userMessage.attachments);
  }

  void _markPendingToolCallsCancelled(String messageId) {
    updateMessage(messageId, (m) {
      if (m.toolCalls.isEmpty) return m;
      final updated = m.toolCalls
          .map(
            (c) => c.isFinished
                ? c
                : c.copyWith(
                    status: ToolCallStatus.cancelled,
                    completedAt: DateTime.now(),
                  ),
          )
          .toList();
      return m.copyWith(toolCalls: updated);
    });
  }

  void _cancelSubscription() {
    _subscription?.cancel();
    _subscription = null;
    _streamingMessageId = null;
  }

  /// Notifies listeners unless the controller has been disposed.
  ///
  /// Stream callbacks can outlive the widget that owns the controller; without
  /// this guard a late chunk throws "used after being disposed".
  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _subscription = null;
    _streamingMessageId = null;
    super.dispose();
  }
}
