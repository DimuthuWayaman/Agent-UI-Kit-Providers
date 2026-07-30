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
  Completer<void>? _consumeCompleter;
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
  ///
  /// Does nothing for an empty iterable, so no-op calls (a common shape when
  /// callers pass through a possibly-empty history) don't trigger a rebuild.
  void addMessages(Iterable<ChatMessage> messages) {
    final list = messages is List<ChatMessage> ? messages : messages.toList();
    if (list.isEmpty) return;
    _messages.addAll(list);
    _safeNotify();
  }

  /// Replaces the message with [id] by applying [update] to it.
  ///
  /// Does nothing when no such message exists, so late-arriving stream events
  /// for a removed message are harmless. Returns whether the message actually
  /// changed, so callers driving several updates in one logical action (see
  /// [stop]) can notify exactly once instead of once per sub-update.
  bool updateMessage(String id, ChatMessage Function(ChatMessage) update) {
    final index = _messages.indexWhere((m) => m.id == id);
    if (index < 0) return false;
    final updated = update(_messages[index]);
    if (updated == _messages[index]) return false;
    _messages[index] = updated;
    _safeNotify();
    return true;
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
    if (_messages.isEmpty && _subscription == null) return;
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
    final messageChanged = updateMessage(
      id,
      (m) => m.copyWith(status: MessageStatus.sent, completedAt: DateTime.now()),
    );
    if (_streamingMessageId == id) {
      _streamingMessageId = null;
      _subscription = null;
      _completeConsume();
      // The message update above already notified when it changed anything;
      // only notify again here for the isStreaming flip itself.
      if (!messageChanged) _safeNotify();
    }
  }

  /// Marks the message with [id] as failed with [error].
  void failMessage(String id, String error) {
    final messageChanged = updateMessage(
      id,
      (m) => m.copyWith(
        status: MessageStatus.failed,
        error: error,
        completedAt: DateTime.now(),
      ),
    );
    if (_streamingMessageId == id) {
      _cancelSubscription();
      if (!messageChanged) _safeNotify();
    }
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
    if (_responder == null) {
      throw StateError(
        'ChatController.send requires a responder. Either pass one to the '
        'constructor or drive streaming with beginAssistantMessage / '
        'appendToken / completeMessage.',
      );
    }
    if (isStreaming) return;
    if (text.trim().isEmpty && (attachments?.isEmpty ?? true)) return;

    await _sendUserMessage(ChatMessage.user(text, attachments: attachments));
  }

  /// Shared core of [send] and [editMessage]'s responder-attached path: adds
  /// [userMessage] as-is (so callers control its id), opens a streaming
  /// assistant message, and drives it through the responder.
  ///
  /// Callers must have already verified a responder is attached.
  Future<void> _sendUserMessage(ChatMessage userMessage) async {
    final responder = _responder!;
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
    _consumeCompleter = completer;

    _subscription = source.listen(
      (chunk) => appendToken(assistantId, chunk),
      onError: (Object error, StackTrace _) {
        failMessage(assistantId, error.toString());
        _completeConsume();
      },
      onDone: () {
        // A stop() between the last chunk and onDone already finalized the
        // message; completing again would resurrect a cancelled stream.
        if (_streamingMessageId == assistantId) {
          completeMessage(assistantId);
        }
        _completeConsume();
      },
      cancelOnError: true,
    );

    return completer.future;
  }

  /// Completes the pending `_consume` future, if any.
  ///
  /// Cancelling `_subscription` (from [stop], [removeMessage], [failMessage]
  /// or [dispose]) permanently prevents `onDone`/`onError` from firing — so
  /// without this, whatever caller is `await`ing [send] or [streamResponse]
  /// would hang forever the moment the stream is cancelled instead of ending
  /// naturally.
  void _completeConsume() {
    final completer = _consumeCompleter;
    _consumeCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  /// Stops the in-flight response, keeping whatever text already arrived.
  ///
  /// This is what the input bar's stop button calls.
  void stop() {
    final id = _streamingMessageId;
    if (id == null) return;
    _cancelSubscription();
    final statusChanged = updateMessage(
      id,
      (m) => m.copyWith(
        status: MessageStatus.stopped,
        completedAt: DateTime.now(),
      ),
    );
    final toolCallsChanged = _markPendingToolCallsCancelled(id);
    // _cancelSubscription already flipped isStreaming to false; that's a
    // real change even when neither update above touched anything, so make
    // sure exactly one notification reaches listeners either way.
    if (!statusChanged && !toolCallsChanged) _safeNotify();
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

    final edited = original.copyWith(text: trimmed);

    if (_responder == null) {
      _messages.add(edited);
      _safeNotify();
      return;
    }

    // Goes through _sendUserMessage rather than send() so the edited message
    // keeps original's id in both branches — send() would mint a fresh one.
    await _sendUserMessage(edited);
  }

  /// Removes the last assistant message and re-sends the user message before
  /// it. Requires a responder.
  Future<void> retryLast() async {
    if (isStreaming) return;
    if (_responder == null) {
      throw StateError(
        'ChatController.retryLast requires a responder. Either pass one to '
        'the constructor or drive regeneration manually.',
      );
    }

    final lastUserIndex = _messages.lastIndexWhere(
      (m) => m.role == ChatRole.user,
    );
    if (lastUserIndex < 0) return;

    final userMessage = _messages[lastUserIndex];
    _messages.removeRange(lastUserIndex, _messages.length);
    _safeNotify();

    await send(userMessage.text, attachments: userMessage.attachments);
  }

  bool _markPendingToolCallsCancelled(String messageId) {
    return updateMessage(messageId, (m) {
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
    _completeConsume();
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
    _cancelSubscription();
    super.dispose();
  }
}
