import 'package:fluent_ui/fluent_ui.dart';

/// One icon per destination, resolved in a single place.
///
/// Fluent's `NavigationPane` takes an `IconData` per item, and the router knows
/// only route paths, so something has to map one to the other. Keeping the map
/// here means adding a route without an icon is visible in one file rather than
/// producing a pane item with a blank square.
abstract final class ShellIcons {
  static IconData forRoute(String location) {
    final path = Uri.parse(location).path;
    if (path.startsWith('/instances')) return FluentIcons.list;
    if (path.startsWith('/download')) return FluentIcons.download;
    if (path.startsWith('/setup')) return FluentIcons.settings;
    if (path.startsWith('/logs')) return FluentIcons.text_document;
    return FluentIcons.play;
  }

  static const instance = FluentIcons.cube_shape;
  static const play = FluentIcons.play;
  static const stop = FluentIcons.stop;
  static const add = FluentIcons.add;
  static const clock = FluentIcons.clock;
  static const warning = FluentIcons.warning;
  static const error = FluentIcons.error_badge;
  static const java = FluentIcons.code;
  static const folder = FluentIcons.folder_open;
  static const search = FluentIcons.search;
  static const download = FluentIcons.download;
  static const check = FluentIcons.check_mark;
  static const edit = FluentIcons.edit;
  static const trash = FluentIcons.delete;
  static const settings = FluentIcons.settings;
}
