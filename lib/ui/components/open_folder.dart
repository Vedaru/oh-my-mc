import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../../l10n/l10n.dart';
import 'app_dialog.dart';
import 'app_button.dart';

/// Opens [path] in the system file manager, creating it first.
///
/// One implementation because there are exactly three platforms to get wrong, and a
/// failure must explain itself: `Process.start` on a machine with no `xdg-open` is a
/// silent no-op otherwise, and "the button does nothing" is the report you get.
Future<void> openFolder(BuildContext context, String path) async {
  await Directory(path).create(recursive: true);

  final (exe, args) = switch (Platform.operatingSystem) {
    'windows' => ('explorer', [path]),
    'macos' => ('open', [path]),
    _ => ('xdg-open', [path]),
  };
  try {
    await Process.start(exe, args, mode: ProcessStartMode.detached);
  } on ProcessException {
    if (!context.mounted) return;
    await m3.showDialog<void>(
      context: context,
      builder: (context) => AppDialog(
        title: context.l10n.instanceOpenFolderFailed,
        content: m3.SelectableText(path),
        actions: [
          AppButton(
            onPressed: () => m3.Navigator.of(context).pop(),
            style: AppButtonStyle.text,
            label: m3.Text(context.l10n.actionClose),
          ),
        ],
      ),
    );
  }
}
