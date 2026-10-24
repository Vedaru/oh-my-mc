import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../theme/app_theme.dart';
import 'hover_row.dart';

/// One row of a Material list.
///
/// M3 fixes the anatomy rather than leaving it to each screen: a
/// **leading** slot (icon, avatar or media), a **content** slot (a required label
/// plus optional supporting text), and a **trailing** slot (text, an icon, a
/// control). The guidelines are explicit about the two rules that are easy to
/// break by accident:
///
/// * "Place supporting visuals and primary text in the same position in each list
///   item. Don't vary the position of elements within a list" — so every row here
///   is the same skeleton, and a caller cannot move the icon or the metadata.
/// * A row is *one* action. "Place supplementary actions [...] in the trailing
///   position" — a second action is a trailing icon button, never a second row.
///
/// Type roles follow the component tokens: label `labelLarge`, supporting
/// `bodyMedium` in `onSurfaceVariant`, trailing text `labelSmall`.
///
/// The whole row is the hit target (a list item is a single tappable area), which
/// is also why a bare text button per row is wrong: repeating the same button
/// label down a list makes every row read as a control instead of an item.
class ListRow extends StatelessWidget {
  const ListRow({
    required this.label,
    super.key,
    this.labelKey,
    this.leadingIcon,
    this.leadingImage,
    this.leadingWidget,
    this.supporting = '',
    this.supportingWidget,
    this.supportingMono = false,
    this.errorText,
    this.trailingText,
    this.trailingTextKey,
    this.trailingControl,
    this.trailingIcon,
    this.trailingTooltip,
    this.onPressed,
    this.onTrailingPressed,
  });

  /// The one required slot: what this row *is*.
  final String label;

  /// Key of the label text, for tests that assert a row exists.
  final Key? labelKey;

  final m3.IconData? leadingIcon;

  /// An image for the leading slot - a pack's `pack.png`, a world's `icon.png`. Takes
  /// the place of [leadingIcon] when present, and is rendered at the same 18 px so the
  /// row's text still starts at the same x in every list.
  final Uint8List? leadingImage;

  /// A widget in the leading slot - an avatar, a status dot - for the rows whose subject
  /// is an *identity* rather than a file. Sized by the caller (a face reads at 28 px, an
  /// icon at 18), and it wins over [leadingIcon]/[leadingImage] when both are given.
  final m3.Widget? leadingWidget;

  /// Optional second line: a path, a status, a description. One line, truncated.
  final String supporting;

  /// A live second line - a server's MOTD and ping - when the text would have to be
  /// composed from an async answer. Takes the place of [supporting].
  final Widget? supportingWidget;

  /// Render [supporting] in the monospace face — paths, ids, argv.
  final bool supportingMono;

  /// Replaces [supporting] when the row's action failed: a failure has to be
  /// visible on the row it belongs to, and in the error colour so it is not read
  /// as another description.
  final String? errorText;

  /// Metadata at the trailing edge: a count, a duration, a size.
  final String? trailingText;
  final Key? trailingTextKey;

  /// The trailing *selection control* of the M3 anatomy - a switch or a checkbox.
  /// It sits at the very edge, after the metadata, because it is the row's state
  /// and not part of its description.
  final Widget? trailingControl;

  final m3.IconData? trailingIcon;
  final String? trailingTooltip;

  /// The row's primary action. Null renders a read-only row.
  final VoidCallback? onPressed;

  /// The supplementary action in the trailing slot.
  final VoidCallback? onTrailingPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = m3.Theme.of(context).colorScheme;
    final hasTrailingAction = trailingIcon != null;

    return HoverRow(
      onTap: onPressed,
      // 10px vertical: a two-line row lands near 56dp, the M3 minimum for a list
      // item with supporting text, without going to the 72dp touch size on a
      // desktop where the pointer is precise.
      padding: const m3.EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      builder: (hovered) => m3.Row(
        children: [
          if (leadingWidget != null) ...[
            const m3.SizedBox(width: 4),
            leadingWidget!,
            const m3.SizedBox(width: 12),
          ] else if (leadingImage != null) ...[
            const m3.SizedBox(width: 4),
            m3.ClipRRect(
              borderRadius: m3.BorderRadius.circular(4),
              child: m3.Image.memory(
                leadingImage!,
                width: 18,
                height: 18,
                fit: m3.BoxFit.cover,
                // A pack whose pack.png is not an image must not paint a red box down
                // the list: fall back to nothing and let the row read as text.
                errorBuilder: (context, error, stack) =>
                    const m3.SizedBox(width: 18, height: 18),
              ),
            ),
            const m3.SizedBox(width: 12),
          ] else if (leadingIcon != null) ...[
            const m3.SizedBox(width: 4),
            m3.Icon(
              leadingIcon,
              size: 18,
              // The leading icon is a cue, so it takes the accent colour only when
              // the row is a live action; a read-only row stays quiet.
              color: onPressed != null
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
            ),
            const m3.SizedBox(width: 12),
          ],
          m3.Expanded(
            child: m3.Column(
              crossAxisAlignment: m3.CrossAxisAlignment.start,
              mainAxisSize: m3.MainAxisSize.min,
              children: [
                m3.Text(
                  label,
                  key: labelKey,
                  style: AppTheme.label(context).copyWith(
                    color: scheme.onSurface,
                    fontWeight: m3.FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: m3.TextOverflow.ellipsis,
                ),
                if (errorText != null ||
                    supporting.isNotEmpty ||
                    supportingWidget != null) ...[
                  const m3.SizedBox(height: 2),
                  if (errorText == null && supportingWidget != null)
                    supportingWidget!
                  else
                    m3.Text(
                      errorText ?? supporting,
                      style:
                          (supportingMono
                                  ? AppTheme.mono(context)
                                  : AppTheme.caption(context))
                              .copyWith(
                                color: errorText == null
                                    ? scheme.onSurfaceVariant
                                    : scheme.error,
                              ),
                      maxLines: 1,
                      overflow: m3.TextOverflow.ellipsis,
                    ),
                ],
              ],
            ),
          ),
          if (trailingText != null) ...[
            const m3.SizedBox(width: 12),
            m3.Text(
              trailingText!,
              key: trailingTextKey,
              style: AppTheme.caption(context)
                  .copyWith(color: scheme.onSurfaceVariant),
              maxLines: 1,
            ),
          ],
          if (hasTrailingAction)
            m3.IconButton(
              onPressed: onTrailingPressed,
              tooltip: trailingTooltip,
              icon: m3.Icon(trailingIcon, size: 16),
              color: scheme.onSurfaceVariant,
              visualDensity: m3.VisualDensity.compact,
            ),
          if (trailingControl != null) ...[
            const m3.SizedBox(width: 4),
            trailingControl!,
          ],
        ],
      ),
    );
  }
}
