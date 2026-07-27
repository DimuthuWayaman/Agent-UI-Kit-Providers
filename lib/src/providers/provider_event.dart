import 'package:flutter/foundation.dart';

import '../models/tool_call.dart';

/// One unit of a provider's streamed response.
///
/// See [TextDelta] and [ToolCallEvent].
@immutable
sealed class ProviderEvent {
  const ProviderEvent();
}

/// A chunk of assistant text.
@immutable
class TextDelta extends ProviderEvent {
  /// The text chunk.
  final String text;

  const TextDelta(this.text);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is TextDelta && other.text == text);

  @override
  int get hashCode => text.hashCode;
}

/// A tool call the model finished requesting, with fully-accumulated
/// arguments.
///
/// Always carries [ToolCallStatus.pending] — executing it and reporting the
/// result back through [ToolCallStatus.success]/[ToolCallStatus.error] is the
/// host app's job, via `ChatController.upsertToolCall`.
@immutable
class ToolCallEvent extends ProviderEvent {
  /// The requested call.
  final ToolCall call;

  const ToolCallEvent(this.call);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ToolCallEvent && other.call == call);

  @override
  int get hashCode => call.hashCode;
}
