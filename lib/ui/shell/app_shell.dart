import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/wallpaper_provider.dart';
import '../../app/router.dart';
import '../../l10n/l10n.dart';
import 'shell_icons.dart';

/// One navigation destination. Derived from [Routes], so a route and its rail
/// item cannot disagree about the path.
class ShellDestination {
  const ShellDestination({
    required this.location,
    required this.label,
    required this.icon,
  });

  final String location;
  final String Function(AppLocalizations l10n) label;
  final m3.IconData icon;
}

/// The destinations, in rail order.
///
/// **启动 is a destination, and it is the first one.**
///
/// It was removed once, on the theory that the instance grid already carried a
/// Play button per card. That is true and beside the point: the launch page is
/// where a *running* session lives - its console and its stop button - so without
/// a tab there was no way back to the page that owns the session. A destination
/// is not a duplicate door when it is the only door to one room.
///
/// Order is PCL's: 启动 / 实例 / 下载 / 日志 / 设置.
List<ShellDestination> destinationsFor(AppLocalizations l10n) => [
  ShellDestination(
    location: Routes.launch,
    label: (l) => l.navLaunch,
    icon: ShellIcons.forRoute(Routes.launch),
  ),
  ShellDestination(
    location: Routes.instances,
    label: (l) => l.navInstances,
    icon: ShellIcons.forRoute(Routes.instances),
  ),
  // Accounts and multiplayer sit above 下载: both are things a session starts with,
  // and both were settings sections nobody found (账户 was 设置 → 通用, 联机 was
  // 设置 → 网络 next to the speed test).
  ShellDestination(
    location: Routes.accounts,
    label: (l) => l.navAccounts,
    icon: ShellIcons.forRoute(Routes.accounts),
  ),
  ShellDestination(
    location: Routes.network,
    label: (l) => l.navNetwork,
    icon: ShellIcons.forRoute(Routes.network),
  ),
  ShellDestination(
    location: Routes.download,
    label: (l) => l.navDownload,
    icon: ShellIcons.forRoute(Routes.download),
  ),
  ShellDestination(
    location: Routes.logs,
    label: (l) => l.navLogs,
    icon: ShellIcons.forRoute(Routes.logs),
  ),
  ShellDestination(
    location: Routes.setup,
    label: (l) => l.navSetup,
    icon: ShellIcons.forRoute(Routes.setup),
  ),
];

/// The application shell: a navigation rail whose selection follows the router
/// rather than its own state.
///
/// The single decision this widget makes is that **the router is the source of
/// truth for navigation state**. A rail would happily keep its own selected
/// index and drift from the URL after a deep link, a back gesture or a
/// programmatic `context.go()`; taking the index from [location] and treating
/// `onDestinationSelected` as a request removes the possibility of the two
/// disagreeing.
///
/// The rail is **fixed-width with the label under each icon**
/// ([m3.NavigationRailLabelType.all]). Two decisions, one reason each: an
/// extended, beside-the-icon rail spent 216 px on five two-character labels, and
/// a collapsible rail animates its own width, which would make the body's
/// constraints depend on a control inside it. A fixed compact rail keeps the
/// icons and their names together and keeps the body's width a constant.
class AppShell extends ConsumerWidget {
  const AppShell({required this.location, required this.child, super.key});

  /// The current location, from `GoRouterState.uri.path`.
  final String location;

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final destinations = destinationsFor(l10n);
    final background = ref.watch(
      appSettingsProvider.select((settings) => settings.backgroundPath),
    );
    final selected = selectedIndexFor(destinations, location);

    // The `Scaffold` is not decoration: without it there is no `Material`
    // ancestor for the page, so every ink splash asserts ("No Material widget
    // found") and any text that does not carry an explicit style falls back to
    // MaterialApp's 48 px red error style. It also supplies the themed
    // background, which a bare Column does not paint at all.
    return m3.Scaffold(
      body: m3.Stack(
        children: [
          if (background != null)
            _Background(
              key: const m3.ValueKey('shell-background'),
              path: background,
              dim: ref.watch(
                appSettingsProvider.select((s) => s.backgroundDim),
              ),
            ),
          m3.Row(
            children: [
              m3.NavigationRail(
                // Labels sit *under* their icon (MD3 `labelType.all`) instead
                // of beside it: the destinations then read as a stack of tabs,
                // and the rail stops charging the page 216 px of width for five
                // two-character labels. The width stays constant, so the body's
                // constraints still do not depend on a control inside the rail -
                // this is a fixed-width rail, not a collapsible one.
                // Icons only when the window is short enough that seven labelled
                // destinations no longer fit: the rail would otherwise overflow, and a
                // clipped destination is a destination the user cannot reach. MD3's
                // icon-only rail is the same control, and its tooltips keep the names.
                labelType: m3.MediaQuery.sizeOf(context).height < 560
                    ? m3.NavigationRailLabelType.none
                    : m3.NavigationRailLabelType.all,
                minWidth: 88,
                selectedIndex: selected,
                onDestinationSelected: (index) =>
                    context.go(destinations[index].location),
                destinations: [
                  for (final destination in destinations)
                    m3.NavigationRailDestination(
                      icon: m3.Icon(destination.icon),
                      label: m3.Text(destination.label(l10n)),
                    ),
                ],
              ),
              m3.Expanded(child: child),
            ],
          ),
        ],
      ),
    );
  }
}

/// A picture behind the whole shell, under a scrim.
///
/// The scrim is the design decision: a launcher is text over whatever the user picked,
/// and text over a bright screenshot is unreadable. It is a `surface` wash whose
/// strength the user chooses (设置 → 外观 → 背景压暗), dense at the top where headings
/// sit and lighter towards the bottom.
///
/// The picture is **blurred**: a sharp photo behind a list competes with the list. Blur
/// keeps the colour and the mood and drops the detail that made rows hard to read.
///
/// It is painted from a decoded `ui.Image` ([wallpaperImageProvider]) rather than through
/// `Image.file`, because that widget paints nothing at all until its decode lands - which
/// is exactly what "the wallpaper does not work" looks like.
class _Background extends ConsumerWidget {
  const _Background({required this.path, required this.dim, super.key});

  final String path;

  /// How much of the surface wash covers the picture (0 = raw wallpaper).
  final double dim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = m3.Theme.of(context).colorScheme;
    final image = ref.watch(wallpaperImageProvider(path)).value;

    return m3.Positioned.fill(
      child: m3.Stack(
        fit: m3.StackFit.expand,
        children: [
          if (image != null)
            m3.ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              // No `color:` here: `RawImage` blends it with `BlendMode.srcIn` by
              // default, which paints the image *as* a solid surface-coloured rectangle -
              // the wallpaper was being replaced by the background colour it sat on.
              child: m3.RawImage(image: image, fit: m3.BoxFit.cover),
            ),
          m3.DecoratedBox(
            decoration: m3.BoxDecoration(
              gradient: m3.LinearGradient(
                begin: m3.Alignment.topLeft,
                end: m3.Alignment.bottomRight,
                colors: [
                  scheme.surface.withValues(alpha: (dim + 0.12).clamp(0, 1)),
                  scheme.surface.withValues(alpha: dim),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Maps a location to a rail index.
///
/// A prefix test, not equality: `/instances/:id` is a child route and must highlight the
/// Instances item, which is the whole reason this is a function with a test rather than
/// an `indexOf`. An unknown path falls back to 0 so a stale deep link still highlights
/// something sane.
int selectedIndexFor(List<ShellDestination> destinations, String location) {
  var best = 0;
  var bestLength = 0;
  for (var i = 0; i < destinations.length; i++) {
    final path = destinations[i].location;
    if (location.startsWith(path) && path.length > bestLength) {
      best = i;
      bestLength = path.length;
    }
  }
  return best;
}
