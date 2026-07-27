import 'package:flutter/foundation.dart';

/// Broad category of an [Attachment], used to pick an icon and preview style.
enum AttachmentKind {
  /// Rendered as an inline thumbnail.
  image,

  /// Rendered as a file chip with a document icon.
  document,

  /// Rendered as a file chip with an audio icon.
  audio,

  /// Rendered as a file chip with a video icon.
  video,

  /// Anything else.
  other,
}

/// A file attached to a [ChatMessage].
///
/// Exactly one of [bytes] or [url] should be set. In-memory [bytes] suit files
/// the user just picked; [url] suits files already uploaded to your backend.
@immutable
class Attachment {
  /// Stable identifier, unique within a message.
  final String id;

  /// Display name, e.g. `invoice.pdf`.
  final String name;

  /// MIME type, e.g. `image/png`. Used to infer [kind] when it is not given.
  final String? mimeType;

  /// Raw file contents, when held in memory.
  final Uint8List? bytes;

  /// Remote location, when the file lives on a server.
  final String? url;

  /// File size in bytes, for the "1.2 MB" label.
  final int? sizeBytes;

  /// Category driving the preview treatment.
  final AttachmentKind kind;

  /// Upload progress from 0.0 to 1.0, or `null` when not uploading.
  final double? uploadProgress;

  Attachment({
    required this.id,
    required this.name,
    this.mimeType,
    this.bytes,
    this.url,
    this.sizeBytes,
    AttachmentKind? kind,
    this.uploadProgress,
  }) : kind = kind ?? _kindFromMime(mimeType, name);

  /// Whether this attachment is still uploading.
  bool get isUploading => uploadProgress != null && uploadProgress! < 1.0;

  /// A human-readable size such as `1.2 MB`, or `null` when [sizeBytes] is
  /// unknown.
  String? get readableSize {
    final size = sizeBytes;
    if (size == null) return null;
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static AttachmentKind _kindFromMime(String? mime, String name) {
    final m = mime?.toLowerCase();
    if (m != null) {
      if (m.startsWith('image/')) return AttachmentKind.image;
      if (m.startsWith('audio/')) return AttachmentKind.audio;
      if (m.startsWith('video/')) return AttachmentKind.video;
      if (m.startsWith('text/') || m.contains('pdf')) {
        return AttachmentKind.document;
      }
    }
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    const images = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic'};
    const docs = {'pdf', 'doc', 'docx', 'txt', 'md', 'csv', 'xls', 'xlsx'};
    const audio = {'mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac'};
    const video = {'mp4', 'mov', 'avi', 'webm', 'mkv'};
    if (images.contains(ext)) return AttachmentKind.image;
    if (docs.contains(ext)) return AttachmentKind.document;
    if (audio.contains(ext)) return AttachmentKind.audio;
    if (video.contains(ext)) return AttachmentKind.video;
    return AttachmentKind.other;
  }

  Attachment copyWith({
    String? id,
    String? name,
    String? mimeType,
    Uint8List? bytes,
    String? url,
    int? sizeBytes,
    AttachmentKind? kind,
    double? uploadProgress,
  }) {
    return Attachment(
      id: id ?? this.id,
      name: name ?? this.name,
      mimeType: mimeType ?? this.mimeType,
      bytes: bytes ?? this.bytes,
      url: url ?? this.url,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      kind: kind ?? this.kind,
      uploadProgress: uploadProgress ?? this.uploadProgress,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Attachment &&
        other.id == id &&
        other.name == name &&
        other.mimeType == mimeType &&
        other.url == url &&
        other.sizeBytes == sizeBytes &&
        other.kind == kind &&
        other.uploadProgress == uploadProgress;
  }

  @override
  int get hashCode =>
      Object.hash(id, name, mimeType, url, sizeBytes, kind, uploadProgress);

  @override
  String toString() => 'Attachment($id, $name, $kind)';
}
