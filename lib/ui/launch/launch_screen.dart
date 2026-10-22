import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/ui/components/app_button.dart';

import '../../app/router.dart';
import '../../core/instance/instance.dart';
import '../../core/launch/launch_handle.dart';
import '../../data/instance_providers.dart';
import '../../core/mc/arch_compat.dart';
import '../../data/install_providers.dart';
import '../../data/java_providers.dart';
import '../../data/launch_providers.dart';
import '../../l10n/l10n.dart';
import '../components/app_banner.dart';
import '../components/hover_row.dart';
import 'version_list_dialog.dart';
import '../components/page_body.dart';
import '../motion/motion.dart';
import '../instances/instance_card.dart';
import '../setup/java_panel.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';

/// The launch screen: which instance is selected, a big play button, and the
/// tail of the log.
///
/// The play button's *state* is the whole point of this screen. A launcher's
/// most common bug is a play button that stays enabled while a game is starting,
/// so the user clicks it three times and gets three JVMs; here the button is
/// driven by [LaunchSession.isBusy] and a second click is a no-op in the
/// controller as well as visually disabled.
class LaunchScreen extends ConsumerWidget {
  const LaunchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(instanceListProvider);
    final session = ref.watch(launchControllerProvider);
    final controller = ref.read(launchControllerProvider.notifier);

    final selected = switch (list) {
      InstanceListReady(:final selected) => selected,
      _ => null,
    };
    final all = switch (list) {
      InstanceListReady(:final instances) => instances,
      _ => const <Instance>[],
    };

    final busy = session.isBusy;

    return PageBody(
      maxWidth: 980,
      scrollable: false,
      child: MotionEntrance(
        // One cascade for the page, not one per child: the launch screen has three
        // blocks, and staggering each of their internals would take a second.
        children: [
          // Nothing selected is a state, not an empty log. Rendering the headline
          // and a disabled Play button above the explanation only said the same
          // thing twice, so the empty state replaces the whole page body.
          if (selected == null)
            const Expanded(child: _NothingSelected())
          else ...[
            _VersionPicker(selected: selected, instances: all),
            const m3.SizedBox(height: 20),
            _PlayRow(
              instance: selected,
              session: session,
              onPlay: busy ? null : () => controller.launch(selected),
              onStop: session.canStop ? controller.stop : null,
            ),
            // The refusal is the useful moment to offer Java: it explains itself
            // in place, and a settings deep link at that point is a round trip
            // the user will not take.
            _JavaOfferArea(instance: selected, session: session),
            // The other refusal the launcher can fix by itself. Kept next to the
            // Java offer because they are the same kind of message: "this is what
            // stopped you, and here is the button that unblocks it".
            _RepairOfferArea(instance: selected, session: session),
            const m3.SizedBox(height: 20),
            // Expanded: the console *is* the bottom half of this page. Sizing it
            // to its content made an idle page end in a thin grey strip that
            // looked like a broken panel, and made the whole layout jump the
            // moment the first log line arrived.
            Expanded(child: _LogTail(lines: session.log)),
          ],
        ],
      ),
    );
  }
}

/// What the page says when no instance is selected.
///
/// A launcher's first run lands here, so this is the one screen that has to
/// explain itself: a disabled Play button with no reason beside it is the most
/// common first-run dead end.
class _NothingSelected extends StatelessWidget {
  const _NothingSelected();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;

    return m3.Center(
      child: m3.ConstrainedBox(
        constraints: const m3.BoxConstraints(maxWidth: 420),
        child: m3.Column(
          mainAxisSize: m3.MainAxisSize.min,
          crossAxisAlignment: m3.CrossAxisAlignment.center,
          children: [
            m3.Icon(
              ShellIcons.instance,
              size: 44,
              color: scheme.onSurfaceVariant,
            ),
            const m3.SizedBox(height: 16),
            m3.Text(
              l10n.noInstanceSelected,
              textAlign: m3.TextAlign.center,
              style: AppTheme.subtitle(context),
            ),
            const m3.SizedBox(height: 8),
            m3.Text(
              l10n.launchEmptyHint,
              textAlign: m3.TextAlign.center,
              style: AppTheme.caption(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
            const m3.SizedBox(height: 20),
            AppButton(
              key: const m3.ValueKey('launch-open-instances'),
              onPressed: () => context.go(Routes.instances),
              style: AppButtonStyle.filled,
              icon: const m3.Icon(ShellIcons.instance, size: 15),
              label: m3.Text(l10n.navInstances),
            ),
          ],
        ),
      ),
    );
  }
}

/// Offers to finish an install that did not complete.
///
/// This is the recovery entry that survives a restart. Before it, the only repair
/// affordance was inside `InstallDone(problemCount > 0)` - a state a *finished*
/// install reaches - so an install killed mid-download (or by a `pkill`) left a
/// version whose JSON exists, whose 67 jars do not, and which had no button
/// anywhere to fix it. The marker file is what makes the state visible; this is
/// what makes it actionable.
class _RepairOfferArea extends ConsumerWidget {
  const _RepairOfferArea({required this.instance, required this.session});

  final Instance instance;
  final LaunchSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final missing = session.blockers.where(
      (b) => b.code == BlockerCode.missingFiles,
    );
    final noVersion = session.blockers.any(
      (b) => b.code == BlockerCode.missingVersion,
    );
    if (missing.isEmpty && !noVersion) return const SizedBox.shrink();

    final busy = ref.watch(installControllerProvider) is InstallRunning;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppBanner(
        key: const ValueKey('launch-repair-offer'),
        severity: BannerSeverity.warning,
        title: noVersion
            ? l10n.launchRepairMissingTitle
            : l10n.launchRepairTitle,
        message: noVersion
            ? l10n.launchRepairMissingBody(instance.versionId)
            : l10n.launchRepairBody(missing.first.count ?? 0),
        actionLabel: noVersion
            ? l10n.launchMissingVersionAction
            : l10n.launchRepairAction,
        onAction: busy
            ? null
            : () {
                if (noVersion) {
                  context.go(Routes.download);
                  return;
                }
                ref
                    .read(installControllerProvider.notifier)
                    .repair(instance.versionId);
                // The progress bar, the byte counter and the install log live on
                // the download page - it is where an install is started, so it is
                // where one is watched. Running a repair here left the user on a
                // page with no feedback at all, which reads as "the button did
                // nothing".
                //
                // Guarded because the page can be mounted without a router (a
                // widget test, or any future embedded use): the repair still runs,
                // and only the jump is skipped.
                if (GoRouter.maybeOf(context) != null) {
                  context.go(Routes.download);
                }
              },
      ),
    );
  }
}

/// Shows the Java panel when the last attempt was refused for want of a JVM.
///
/// Watches the requirement lazily: resolving it opens the version JSON and scans
/// for JVMs, which is wasted work for a launch that never mentioned Java.
class _JavaOfferArea extends ConsumerWidget {
  const _JavaOfferArea({required this.instance, required this.session});

  final Instance instance;
  final LaunchSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final needsJava = session.blockers.any(
      (b) =>
          b.code == BlockerCode.noRuntime || b.code == BlockerCode.javaTooOld,
    );
    if (!needsJava) return const SizedBox.shrink();

    final requirement = ref.watch(javaRequirementProvider(instance.versionId));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: requirement.when(
        loading: () => const SizedBox.shrink(),
        // A version file that cannot be read is not something the panel can
        // fix, so it reports the same "install it first" as a missing version
        // rather than leaking the exception text into the UI.
        error: (error, _) => const JavaPanel(
          requirement: JavaRequirementUnavailable(
            JavaUnavailableReason.versionNotInstalled,
          ),
        ),
        data: (value) => JavaPanel(requirement: value),
      ),
    );
  }
}

/// The instance name plus its version, animated so a selection change reads as
/// a change rather than as text swapping in place.
/// The version picker - PCL's version card.
///
/// A launch page's first question is *which* version, so the answer is a control,
/// not a label: clicking it lists every instance, and the last item is the
/// management screen (which is where creation lives, exactly like PCL's version
/// list dialog). The selection goes through [instanceListProvider] so the choice
/// survives a restart and every screen agrees on it.
/// The version card - PCL's launch page subject.
///
/// The card is the selector: clicking it opens [VersionListDialog] (versions,
/// their settings, and the way to create or manage them). It used to be a
/// `PopupMenuButton`: a menu anchored under a 500 px card, sized to its widest
/// row, floating over the log. That answered "which one" and nothing else, and it
/// read as a broken widget rather than a version list - which is exactly what a
/// user asked about it.
class _VersionPicker extends ConsumerWidget {
  const _VersionPicker({required this.selected, required this.instances});

  final Instance? selected;
  final List<Instance> instances;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    final instance = selected;

    // The loader and the version are what tell two instances apart; when the
    // instance is *named* after its version, repeating it in the subtitle is
    // noise ("26.2" over "26.2").
    final subtitle = instance == null
        ? l10n.noInstanceSelected
        : [
            if (instance.displayName != instance.versionId) instance.versionId,
            if (instance.loader.isModded)
              '${instance.loader.label} ${instance.loaderVersion ?? ''}'.trim(),
            if (instance.displayName == instance.versionId &&
                !instance.loader.isModded)
              l10n.loaderVanilla,
          ].join('  ·  ');

    return HoverRow(
      key: const m3.ValueKey('launch-version-picker'),
      onTap: () => showVersionList(context),
      padding: const m3.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      builder: (hovered) => m3.Row(
        children: [
          m3.Icon(
            instance != null && instance.loader.isModded
                ? ShellIcons.addon
                : ShellIcons.instance,
            size: 26,
            color: scheme.primary,
          ),
          const m3.SizedBox(width: 14),
          m3.Expanded(
            child: m3.Column(
              crossAxisAlignment: m3.CrossAxisAlignment.start,
              children: [
                m3.Text(
                  instance?.displayName ?? l10n.noInstanceSelected,
                  key: const m3.ValueKey('launch-version-name'),
                  style: AppTheme.title(context),
                  maxLines: 1,
                  overflow: m3.TextOverflow.ellipsis,
                ),
                const m3.SizedBox(height: 2),
                m3.Text(
                  subtitle,
                  style: AppTheme.caption(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: m3.TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          m3.Icon(m3.Icons.expand_more, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _PlayRow extends StatelessWidget {
  const _PlayRow({
    required this.instance,
    required this.session,
    required this.onPlay,
    required this.onStop,
  });

  final Instance? instance;
  final LaunchSession session;
  final VoidCallback? onPlay;
  final Future<void> Function()? onStop;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final motion = MotionScope.of(context);
    final scheme = m3.Theme.of(context).colorScheme;

    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.start,
      children: [
        m3.Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: m3.WrapCrossAlignment.center,
          children: [
            // Press feedback: the button gives under the pointer and springs back.
            // It reads as "heard you" on the one control the whole screen exists
            // for; motion-off returns the plain button, no listener (PLAN-M11 §3.4).
            Emphasis(
              child: AppButton(
                key: const m3.ValueKey('play'),
                onPressed: onPlay,
                style: AppButtonStyle.filled,
                size: AppButtonSize.lg,
                // A pulsing dot, not a spinner: the launch is one indeterminate wait,
                // and a dot says "alive" without pretending to know how far along it
                // is. AmbientLoop renders its resting frame and creates no ticker
                // when motion is off.
                icon: session.isBusy
                    ? AmbientLoop(
                        tween: Tween<double>(begin: 0.35, end: 1),
                        duration: Durations.slow,
                        builder: (context, value, _) => m3.Opacity(
                          opacity: value,
                          child: m3.SizedBox(
                            width: 10,
                            height: 10,
                            child: m3.DecoratedBox(
                              decoration: m3.BoxDecoration(
                                color: scheme.onPrimary,
                                shape: m3.BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      )
                    : const m3.Icon(ShellIcons.play, size: 16),
                label: m3.Text(
                  session.isBusy ? l10n.launching : l10n.playButton,
                ),
              ),
            ),
            // PCL puts version settings right next to Play, because that is the moment
            // the user notices "this one needs more memory / another Java".
            if (instance != null)
              AppButton(
                key: const m3.ValueKey('launch-open-settings'),
                // Push, so the run view stays underneath: settings is a visit,
                // and back returns to the log and the stop button.
                onPressed: () =>
                    context.push(Routes.instanceDetail(instance!.id)),
                style: AppButtonStyle.outlined,
                icon: const m3.Icon(ShellIcons.settings, size: 14),
                label: m3.Text(l10n.instanceOpen),
              ),
            // The stop button only exists while something can be stopped, and it
            // fades rather than popping so the row does not jump.
            m3.AnimatedSwitcher(
              duration: motion.of(Durations.fast),
              switchInCurve: MotionCurves.enter,
              switchOutCurve: MotionCurves.exit,
              child: session.canStop
                  ? AppButton(
                      key: const m3.ValueKey('stop'),
                      onPressed: onStop,
                      style: AppButtonStyle.outlined,
                      icon: const m3.Icon(ShellIcons.stop, size: 13),
                      label: m3.Text(l10n.stopButton),
                    )
                  : const m3.SizedBox.shrink(key: m3.ValueKey('no-stop')),
            ),
          ],
        ),
        if (session.state == LaunchState.exited) ...[
          const m3.SizedBox(height: 10),
          _ExitBadge(
            exitCode: session.exitCode,
            failure: session.failure,
            uptime: session.uptime,
          ),
        ],
      ],
    );
  }
}

class _ExitBadge extends StatelessWidget {
  const _ExitBadge({
    required this.exitCode,
    required this.failure,
    required this.uptime,
  });

  final int? exitCode;
  final LaunchFailure? failure;
  final Duration uptime;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    final failed = failure != null || (exitCode != null && exitCode != 0);

    // A non-zero exit is not necessarily an error the user can fix (the game
    // exits 1 on some crashes and on some clean quits), so the wording reports
    // the code instead of claiming a crash.
    final text = failure != null
        ? switch (failure!) {
            LaunchFailure.spawnFailed => l10n.launchFailedSpawn,
            LaunchFailure.refused => l10n.launchFailedRefused,
            LaunchFailure.prepareFailed => l10n.launchFailedPrepare,
          }
        : l10n.launchExited(exitCode ?? 0, formatPlaytime(uptime));

    final color = failed
        ? AppTheme.status(context).warning
        : scheme.onSurfaceVariant;
    return m3.Row(
      mainAxisSize: m3.MainAxisSize.min,
      children: [
        m3.Icon(
          failed ? ShellIcons.warning : ShellIcons.clock,
          size: 13,
          color: color,
        ),
        const m3.SizedBox(width: 6),
        m3.Text(text, style: AppTheme.caption(context).copyWith(color: color)),
      ],
    );
  }
}

/// The last lines of output, newest at the bottom.
///
/// Rendered as a `ListView` over the session's own bounded list: the controller
/// already keeps the newest 2000 lines, so this widget never needs to window
/// them itself. Auto-scrolling follows the tail only while the user is already at
/// the bottom, so scrolling up to read a stack trace is not undone by the next
/// log line.
class _LogTail extends StatefulWidget {
  const _LogTail({required this.lines});

  final List<LogLine> lines;

  @override
  State<_LogTail> createState() => _LogTailState();
}

class _LogTailState extends State<_LogTail> {
  final _controller = ScrollController();
  var _stickToBottom = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    // 24px of slack: "at the bottom" in practice, not mathematically.
    _stickToBottom = position.pixels >= position.maxScrollExtent - 24;
  }

  @override
  void didUpdateWidget(_LogTail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lines.length != oldWidget.lines.length && _stickToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        _controller.jumpTo(_controller.position.maxScrollExtent);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;

    // One surface, no inner box: the console is a single filled panel, and the
    // border it used to draw around its own text was a second frame inside the
    // first. Its height comes from the page (Expanded), so an idle console is as
    // tall as a busy one and nothing reflows when output starts.
    return m3.Container(
      key: const m3.ValueKey('launch-log-console'),
      decoration: m3.BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: m3.BorderRadius.circular(16),
      ),
      clipBehavior: m3.Clip.antiAlias,
      child: m3.Column(
        crossAxisAlignment: m3.CrossAxisAlignment.stretch,
        children: [
          m3.Padding(
            padding: const m3.EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: m3.Row(
              children: [
                m3.Text(l10n.navLogs, style: AppTheme.label(context)),
                const m3.SizedBox(width: 8),
                if (widget.lines.isNotEmpty)
                  m3.Text(
                    '${widget.lines.length}',
                    key: const m3.ValueKey('launch-log-count'),
                    style: AppTheme.mono(context)
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          m3.Expanded(
            child: widget.lines.isEmpty
                ? m3.Center(
                    child: m3.Column(
                      mainAxisSize: m3.MainAxisSize.min,
                      children: [
                        m3.Text(
                          l10n.logsEmpty,
                          style: AppTheme.body(context)
                              .copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const m3.SizedBox(height: 4),
                        // A panel this large has to say what will fill it: a bare
                        // "no output" reads as a console that does not work.
                        m3.Text(
                          l10n.launchLogEmptyHint,
                          style: AppTheme.caption(context)
                              .copyWith(color: scheme.outline),
                        ),
                      ],
                    ),
                  )
                : m3.ListView.builder(
                    controller: _controller,
                    padding: const m3.EdgeInsets.fromLTRB(16, 0, 16, 14),
                    itemCount: widget.lines.length,
                    itemBuilder: (context, index) {
                      final line = widget.lines[index];
                      return m3.Text(
                        line.text,
                        style: AppTheme.mono(context).copyWith(
                          color: line.channel == LogChannel.stderr
                              ? scheme.error
                              : scheme.onSurface,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
