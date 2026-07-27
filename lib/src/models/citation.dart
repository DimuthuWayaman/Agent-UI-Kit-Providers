import 'package:flutter/foundation.dart';

/// A source the assistant referenced when producing a message.
///
/// Rendered by `CitationChip` and, when a message carries several, by
/// `CitationList` beneath the bubble.
@immutable
class Citation {
  /// Stable identifier, unique within a message.
  final String id;

  /// Human-readable source title.
  final String title;

  /// Canonical link to the source, if it has one.
  final String? url;

  /// Short excerpt shown on hover or expansion.
  final String? snippet;

  /// Retrieval confidence from 0.0 to 1.0, when your pipeline reports it.
  final double? score;

  const Citation({
    required this.id,
    required this.title,
    this.url,
    this.snippet,
    this.score,
  });

  /// The bare host of [url] (`docs.flutter.dev`), suitable as a compact label.
  ///
  /// Falls back to [title] when there is no parseable URL.
  String get displayLabel {
    final u = url;
    if (u == null) return title;
    final parsed = Uri.tryParse(u);
    final host = parsed?.host;
    if (host == null || host.isEmpty) return title;
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  Citation copyWith({
    String? id,
    String? title,
    String? url,
    String? snippet,
    double? score,
  }) {
    return Citation(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      snippet: snippet ?? this.snippet,
      score: score ?? this.score,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Citation &&
        other.id == id &&
        other.title == title &&
        other.url == url &&
        other.snippet == snippet &&
        other.score == score;
  }

  @override
  int get hashCode => Object.hash(id, title, url, snippet, score);

  @override
  String toString() => 'Citation($id, $title)';
}
