import 'package:flutter/material.dart';

import '../models/attachment.dart';
import '../theme/agent_theme.dart';

/// Icon representing an attachment's [AttachmentKind].
IconData iconForAttachment(AttachmentKind kind) => switch (kind) {
      AttachmentKind.image => Icons.image_outlined,
      AttachmentKind.document => Icons.description_outlined,
      AttachmentKind.audio => Icons.audiotrack_outlined,
      AttachmentKind.video => Icons.videocam_outlined,
      AttachmentKind.other => Icons.attach_file_rounded,
    };

/// A single attachment rendered as a thumbnail (images) or a file chip.
class AttachmentPreview extends StatelessWidget {
  /// The attachment to display.
  final Attachment attachment;

  /// Called when tapped.
  final VoidCallback? onTap;

  /// Called when the remove affordance is tapped. Hidden when null.
  final VoidCallback? onRemove;

  /// Render at a reduced size, for use inside a message bubble.
  final bool compact;

  const AttachmentPreview({
    super.key,
    required this.attachment,
    this.onTap,
    this.onRemove,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);
    final isImage = attachment.kind == AttachmentKind.image &&
        (attachment.bytes != null || attachment.url != null);

    final child = isImage ? _buildThumbnail(context, theme) : _buildChip(context, theme);

    return Semantics(
      label: '${attachment.name}'
          '${attachment.readableSize != null ? ', ${attachment.readableSize}' : ''}',
      button: onTap != null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: theme.radii.mediumRadius,
            child: child,
          ),
          if (attachment.isUploading)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colors.overlay,
                    borderRadius: theme.radii.mediumRadius,
                  ),
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: attachment.uploadProgress,
                      valueColor:
                          const AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          if (onRemove != null)
            Positioned(
              top: -6,
              right: -6,
              child: _RemoveButton(onPressed: onRemove!),
            ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(BuildContext context, AgentThemeData theme) {
    final size = compact ? 96.0 : 120.0;
    final image = attachment.bytes != null
        ? Image.memory(attachment.bytes!, fit: BoxFit.cover)
        : Image.network(attachment.url!, fit: BoxFit.cover);

    return ClipRRect(
      borderRadius: theme.radii.mediumRadius,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: theme.colors.surfaceContainerHigh, child: image),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(BuildContext context, AgentThemeData theme) {
    final colors = theme.colors;
    final size = attachment.readableSize;

    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: EdgeInsets.symmetric(
        horizontal: theme.spacing.md,
        vertical: theme.spacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: theme.radii.mediumRadius,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            iconForAttachment(attachment.kind),
            size: 18,
            color: colors.accent,
          ),
          SizedBox(width: theme.spacing.sm),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.bodySmall
                      .copyWith(color: colors.textPrimary),
                ),
                if (size != null)
                  Text(
                    size,
                    style: theme.typography.caption
                        .copyWith(color: colors.textTertiary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A horizontally wrapping row of [AttachmentPreview]s.
class AttachmentPreviewList extends StatelessWidget {
  /// Attachments to display.
  final List<Attachment> attachments;

  /// Called with the index of a tapped attachment.
  final ValueChanged<int>? onTap;

  /// Called with the index of an attachment to remove. Hidden when null.
  final ValueChanged<int>? onRemove;

  /// Render at reduced size.
  final bool compact;

  const AttachmentPreviewList({
    super.key,
    required this.attachments,
    this.onTap,
    this.onRemove,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    final theme = AgentTheme.of(context);

    return Wrap(
      spacing: theme.spacing.sm,
      runSpacing: theme.spacing.sm,
      children: [
        for (var i = 0; i < attachments.length; i++)
          AttachmentPreview(
            attachment: attachments[i],
            compact: compact,
            onTap: onTap == null ? null : () => onTap!(i),
            onRemove: onRemove == null ? null : () => onRemove!(i),
          ),
      ],
    );
  }
}

class _RemoveButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _RemoveButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);

    return Semantics(
      button: true,
      label: 'Remove attachment',
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: theme.colors.textPrimary,
            shape: BoxShape.circle,
            // onInverseSurface, not surface: a translucent theme sets surface
            // to transparent, which made the glyph and ring vanish entirely.
            border: Border.all(
              color: theme.colors.onInverseSurface,
              width: 1.5,
            ),
          ),
          child: Icon(
            Icons.close_rounded,
            size: 12,
            color: theme.colors.onInverseSurface,
          ),
        ),
      ),
    );
  }
}
