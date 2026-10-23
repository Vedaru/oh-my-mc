import 'package:material_ui/material_ui.dart' as m3;

/// One icon per destination, resolved in a single place.
///
/// A navigation rail takes an `IconData`, and the router knows only route paths,
/// so something has to map one to the other. Keeping the map here means adding a
/// route without an icon is visible in one file rather than producing a rail
/// item with a blank square.
///
/// The Material glyph set rather than a third-party icon package: `material_ui`
/// is already the design system, and `uses-material-design: true` ships the font.
/// The previous Lucide package subclassed `IconData`, which Flutter 3.47 made
/// `final`, so it no longer compiled at all.
abstract final class ShellIcons {
  static m3.IconData forRoute(String location) {
    final path = Uri.parse(location).path;
    if (path.startsWith('/instances')) return list;
    if (path.startsWith('/download')) return download;
    if (path.startsWith('/setup')) return settings;
    if (path.startsWith('/logs')) return document;
    return play;
  }

  static const list = m3.Icons.list_alt;
  static const download = m3.Icons.download;
  static const settings = m3.Icons.settings;
  static const document = m3.Icons.description;
  static const play = m3.Icons.play_arrow;
  static const stop = m3.Icons.stop_circle;

  static const instance = m3.Icons.inventory_2;
  static const add = m3.Icons.add;
  static const clock = m3.Icons.schedule;
  static const warning = m3.Icons.warning_amber;
  static const error = m3.Icons.error_outline;
  static const java = m3.Icons.terminal;
  static const folder = m3.Icons.folder_open;
  static const search = m3.Icons.search;
  static const check = m3.Icons.check;
  static const checkCircle = m3.Icons.check_circle;
  static const checkCircleFilled = m3.Icons.check_circle;
  static const edit = m3.Icons.edit;
  static const trash = m3.Icons.delete;
  static const addon = m3.Icons.extension;
  static const back = m3.Icons.arrow_back;
  static const refresh = m3.Icons.refresh;
  static const close = m3.Icons.close;
  static const copy = m3.Icons.content_copy;
  static const openExternal = m3.Icons.open_in_new;
  static const mods = m3.Icons.extension;
  static const resourcePacks = m3.Icons.palette;
  static const shaderPacks = m3.Icons.auto_awesome;
  static const saves = m3.Icons.map;
  static const network = m3.Icons.lan;
  static const info = m3.Icons.info_outline;
}
