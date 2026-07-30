import 'package:flutter/foundation.dart';

/// Sentinel default for a `copyWith` parameter, distinguishing "omitted" (use
/// the current value) from an explicit `null` (clear the field).
const Object _unset = Object();

/// Lifecycle of a single tool/function call.
enum ToolCallStatus {
  /// The model requested the call; execution has not started.
  pending,

  /// Currently executing.
  running,

  /// Completed successfully.
  success,

  /// Failed. [ToolCall.error] carries the reason.
  error,

  /// Aborted before completion, usually because the user stopped generation.
  cancelled,
}

/// A tool (a.k.a. function) invocation made by the model.
///
/// This mirrors the shape every major agent API returns — Anthropic's
/// `tool_use`/`tool_result`, OpenAI's `function_call`, Gemini's
/// `functionCall` — so adapting a provider response is a field mapping rather
/// than a redesign.
@immutable
class ToolCall {
  /// Provider-assigned call identifier.
  final String id;

  /// Tool name, e.g. `get_weather`.
  final String name;

  /// Current lifecycle state.
  final ToolCallStatus status;

  /// Arguments the model passed, pretty-printed for display.
  final String? input;

  /// Result returned to the model, pretty-printed for display.
  final String? output;

  /// Failure reason when [status] is [ToolCallStatus.error].
  final String? error;

  /// When execution began.
  final DateTime? startedAt;

  /// When execution finished.
  final DateTime? completedAt;

  const ToolCall({
    required this.id,
    required this.name,
    this.status = ToolCallStatus.pending,
    this.input,
    this.output,
    this.error,
    this.startedAt,
    this.completedAt,
  });

  /// Wall-clock execution time, or `null` while still running.
  Duration? get duration {
    final start = startedAt;
    final end = completedAt;
    if (start == null || end == null) return null;
    return end.difference(start);
  }

  /// Execution time formatted compactly (`820ms`, `2.4s`), or `null`.
  String? get readableDuration {
    final d = duration;
    if (d == null) return null;
    if (d.inMilliseconds < 1000) return '${d.inMilliseconds}ms';
    if (d.inSeconds < 60) {
      return '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
    }
    return '${d.inMinutes}m ${d.inSeconds % 60}s';
  }

  /// Whether the call has reached a terminal state.
  bool get isFinished =>
      status == ToolCallStatus.success ||
      status == ToolCallStatus.error ||
      status == ToolCallStatus.cancelled;

  /// Whether there is anything to reveal when expanded.
  bool get hasDetails =>
      (input?.isNotEmpty ?? false) ||
      (output?.isNotEmpty ?? false) ||
      (error?.isNotEmpty ?? false);

  /// Returns a copy with the given fields replaced.
  ///
  /// [input], [output] and [error] default to a sentinel rather than `null`,
  /// so omitting them preserves the current value while passing `null`
  /// explicitly clears it — e.g. `copyWith(status: ToolCallStatus.running,
  /// error: null)` clears a previous failure when retrying the same call.
  ToolCall copyWith({
    String? id,
    String? name,
    ToolCallStatus? status,
    Object? input = _unset,
    Object? output = _unset,
    Object? error = _unset,
    DateTime? startedAt,
    DateTime? completedAt,
  }) {
    return ToolCall(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
      input: identical(input, _unset) ? this.input : input as String?,
      output: identical(output, _unset) ? this.output : output as String?,
      error: identical(error, _unset) ? this.error : error as String?,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ToolCall &&
        other.id == id &&
        other.name == name &&
        other.status == status &&
        other.input == input &&
        other.output == output &&
        other.error == error &&
        other.startedAt == startedAt &&
        other.completedAt == completedAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        status,
        input,
        output,
        error,
        startedAt,
        completedAt,
      );

  @override
  String toString() => 'ToolCall($id, $name, $status)';
}
