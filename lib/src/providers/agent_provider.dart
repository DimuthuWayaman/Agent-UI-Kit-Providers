import 'package:flutter/foundation.dart';

import '../controllers/chat_controller.dart';
import '../models/attachment.dart';
import '../models/chat_message.dart';
import 'provider_event.dart';

/// Thrown when a provider's HTTP request fails.
@immutable
class AgentProviderException implements Exception {
  /// The HTTP status code returned.
  final int statusCode;

  /// The raw response body, for diagnostics.
  final String body;

  /// Creates an exception for a failed provider request.
  const AgentProviderException(this.statusCode, this.body);

  @override
  String toString() => 'AgentProviderException($statusCode): $body';
}

/// Base type for model-provider integrations.
///
/// See `OpenRouterProvider` and `GeminiProvider` for concrete
/// implementations. A provider knows how to turn a conversation into a
/// request and a streamed response into [ProviderEvent]s; everything else —
/// plugging into [ChatController] — is handled here so each provider only
/// implements [streamEvents].
abstract class AgentProvider {
  /// Const constructor for subclasses.
  const AgentProvider();

  /// Streams structured events for [conversation]'s next assistant turn.
  ///
  /// [conversation] is oldest-first; its last element is the new user turn.
  Stream<ProviderEvent> streamEvents(List<ChatMessage> conversation);

  /// Adapts this provider to [AgentResponder], for [ChatController]'s managed
  /// `send()`.
  ///
  /// Tool calls are dropped in this mode — a `Stream<String>` cannot
  /// represent them. Use [sendMessage] when the model may call tools.
  ///
  /// Pass [history] (typically `() => controller.messages`) so the provider
  /// sees prior turns.
  AgentResponder asResponder({List<ChatMessage> Function()? history}) {
    return (userMessage) {
      final base = history != null ? history() : const <ChatMessage>[];
      // ChatController.send() calls beginAssistantMessage() -- which appends
      // an *empty* streaming placeholder -- before invoking the responder, so
      // `base` already ends with that placeholder by the time this closure
      // runs. Strip empty assistant messages so the provider sees the user's
      // message as the true last turn, not an empty stub.
      final conversation = [
        for (final m in base)
          if (!(m.role == ChatRole.assistant && m.isEmpty)) m,
      ];
      // Stream has no whereType() (that's an Iterable method) -- narrow with
      // where()+cast() instead.
      return streamEvents(conversation)
          .where((event) => event is TextDelta)
          .cast<TextDelta>()
          .map((event) => event.text);
    };
  }

  /// Drives [controller]'s manual streaming API directly, so tool calls
  /// surface as `ToolCall`s instead of being dropped.
  ///
  /// Mirrors what [ChatController.send] does for plain text: adds a user
  /// message, opens a streaming assistant message, and finalizes it on
  /// completion or failure.
  ///
  /// Note: [ChatController.stop] cancels its own internal subscription, but
  /// this method drives the controller with a plain `await for` rather than
  /// through that subscription, so `stop()` cannot cancel the underlying HTTP
  /// request directly. It still stops new tokens from reaching the UI —
  /// each loop iteration checks whether this message is still the
  /// controller's active stream and returns early once `stop()` has cleared
  /// it — but the request keeps draining server-side until it completes; its
  /// remaining output is simply discarded.
  Future<void> sendMessage(
    ChatController controller,
    String text, {
    List<Attachment>? attachments,
  }) async {
    final userMessage = ChatMessage.user(text, attachments: attachments);
    controller.addMessage(userMessage);
    // Snapshot before beginAssistantMessage() adds the empty streaming
    // placeholder -- that placeholder must not be sent as a conversation turn.
    final conversation = controller.messages;
    final assistantId = controller.beginAssistantMessage();

    try {
      await for (final event in streamEvents(conversation)) {
        if (controller.streamingMessageId != assistantId) return;
        switch (event) {
          case TextDelta(text: final chunk):
            controller.appendToken(assistantId, chunk);
          case ToolCallEvent(:final call):
            controller.upsertToolCall(assistantId, call);
        }
      }
      if (controller.streamingMessageId == assistantId) {
        controller.completeMessage(assistantId);
      }
    } catch (error) {
      if (controller.streamingMessageId == assistantId) {
        controller.failMessage(assistantId, error.toString());
      }
    }
  }

  /// Releases resources held by this provider.
  ///
  /// Closes an internally-created `http.Client`; a client passed in by the
  /// caller is left open for the caller to manage.
  void dispose();
}
