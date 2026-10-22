import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../theme/app_theme.dart';

/// A Material alert dialog.
///
/// Every dialog in the app has the same shape - a title, a body, and a row of
/// actions - so the composition lives here. [title] doubles as the accessibility
/// label: a dialog whose spoken name differs from its visible heading is a
/// problem the user cannot see, so the two are not separately configurable.
class AppDialog extends StatelessWidget {
  const AppDialog({
    required this.title,
    this.content,
    this.actions = const [],
    super.key,
  });

  final String title;
  final Widget? content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return m3.AlertDialog(
      semanticLabel: title,
      title: m3.Text(title, style: AppTheme.title(context)),
      content: content,
      actions: actions,
    );
  }
}
