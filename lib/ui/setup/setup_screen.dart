import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../../app/providers.dart';
import '../../core/instance/memory.dart';
import '../../data/settings.dart';
import '../../l10n/l10n.dart';
import '../motion/motion.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';
import 'java_panel.dart';
import '../components/app_radio_group.dart';
import '../components/app_slider.dart';
import '../components/app_switch.dart';
import '../components/app_text_field.dart';

/// Everything the launcher lets a user change.
///
/// Each control writes through [AppSettingsNotifier] immediately, so there is no
/// Save button and no unsaved state to lose. The Java section manages files
/// rather than settings, which is why it is a panel of its own.
class SetupScreen extends ConsumerWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);

    return MotionEntrance(
      children: [
        m3.Padding(
          padding: const m3.EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: m3.Text(l10n.navSetup, style: AppTheme.title(context)),
        ),
        m3.Expanded(
          child: m3.ListView(
            padding: const m3.EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              _Section(
                title: l10n.setupLanguage,
                children: [
                  _SettingRow(
                    label: l10n.setupLanguage,
                    hint: l10n.setupLanguageHint,
                    child: _Choice<LanguagePreference>(
                      keyPrefix: 'language',
                      value: settings.language,
                      options: {
                        LanguagePreference.system: l10n.themeSystem,
                        LanguagePreference.english: l10n.languageEnglish,
                        LanguagePreference.chinese: l10n.languageChinese,
                      },
                      onChanged: notifier.setLanguage,
                    ),
                  ),
                ],
              ),
              const m3.SizedBox(height: 12),
              _Section(
                title: l10n.setupUi,
                children: [
                  _SettingRow(
                    label: l10n.setupThemeMode,
                    hint: l10n.setupThemeHint,
                    child: _Choice<ThemePreference>(
                      keyPrefix: 'theme',
                      value: settings.theme,
                      options: {
                        ThemePreference.system: l10n.themeSystem,
                        ThemePreference.light: l10n.themeLight,
                        ThemePreference.dark: l10n.themeDark,
                      },
                      onChanged: notifier.setTheme,
                    ),
                  ),
                  _SettingRow(
                    label: l10n.setupMotion,
                    hint: l10n.setupMotionHint,
                    child: m3.Row(
                      children: [
                        AppSwitch(
                          key: const m3.ValueKey('setup-motion'),
                          value: settings.uiAnimations,
                          // Turning this on cannot override the OS accessibility
                          // setting: MotionScope ORs them.
                          onChanged: notifier.setUiAnimations,
                          label: l10n.setupMotion,
                        ),
                        const m3.SizedBox(width: 10),
                        m3.Text(
                          settings.uiAnimations
                              ? l10n.setupMotionOn
                              : l10n.setupMotionOff,
                          style: AppTheme.body(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const m3.SizedBox(height: 12),
              _Section(
                title: l10n.setupLaunch,
                children: [
                  _PlayerNameRow(settings: settings),
                  _GlobalMemoryRow(settings: settings),
                ],
              ),
              const m3.SizedBox(height: 12),
              _Section(
                title: l10n.setupJava,
                children: const [JavaRuntimeList()],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = m3.Theme.of(context).colorScheme;
    return m3.Container(
      padding: const m3.EdgeInsets.all(14),
      decoration: m3.BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: m3.BorderRadius.circular(14),
        border: m3.Border.all(color: scheme.outlineVariant),
      ),
      child: m3.Column(
        crossAxisAlignment: m3.CrossAxisAlignment.stretch,
        children: [
          m3.Text(title, style: AppTheme.label(context)),
          const m3.SizedBox(height: 10),
          for (final child in children) ...[
            child,
            const m3.SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

/// Label and hint on the left, control on the right.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    required this.hint,
    required this.child,
  });

  final String label;
  final String hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = m3.Theme.of(context).colorScheme;
    return m3.Row(
      crossAxisAlignment: m3.CrossAxisAlignment.start,
      children: [
        m3.SizedBox(
          width: 200,
          child: m3.Column(
            crossAxisAlignment: m3.CrossAxisAlignment.start,
            children: [
              m3.Padding(
                padding: const m3.EdgeInsets.only(top: 6),
                child: m3.Text(label, style: AppTheme.body(context)),
              ),
              m3.Padding(
                padding: const m3.EdgeInsets.only(top: 2),
                child: m3.Text(
                  hint,
                  style: AppTheme.caption(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        m3.Expanded(
          child: m3.Align(
            alignment: m3.AlignmentDirectional.centerStart,
            child: child,
          ),
        ),
      ],
    );
  }
}

/// Radio buttons over an ordered map: every one of these settings is a fixed set
/// of choices with a label each, so a dropdown would hide the alternatives.
class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.value,
    required this.options,
    required this.onChanged,
    this.keyPrefix = 'choice',
  });

  final T value;
  final Map<T, String> options;
  final void Function(T value) onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return AppRadioGroup<T>(
      value: value,
      options: options,
      onChanged: onChanged,
      keyPrefix: keyPrefix,
    );
  }
}

/// Offline name, shown to other players. Validated by the same rule the store
/// applies on load, so an in-game rejection cannot come from this field.
class _PlayerNameRow extends ConsumerStatefulWidget {
  const _PlayerNameRow({required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<_PlayerNameRow> createState() => _PlayerNameRowState();
}

class _PlayerNameRowState extends ConsumerState<_PlayerNameRow> {
  late final _controller = TextEditingController(
    text: widget.settings.playerName,
  );
  final _focus = FocusNode();

  static final _valid = RegExp(r'^[A-Za-z0-9_]{3,16}$');

  @override
  void initState() {
    super.initState();
    _focus.addListener(_commitOnBlur);
  }

  @override
  void dispose() {
    _focus.removeListener(_commitOnBlur);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _commitOnBlur() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    final name = _controller.text.trim();
    if (name == widget.settings.playerName) return;
    // An invalid name reverts rather than being stored: the store would fall
    // back to "Player", which looks like the edit was silently lost.
    if (!_valid.hasMatch(name)) {
      _controller.text = widget.settings.playerName;
      return;
    }
    ref
        .read(appSettingsProvider.notifier)
        .set(widget.settings.copyWith(playerName: name));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _SettingRow(
      label: l10n.setupPlayerName,
      hint: l10n.setupPlayerNameHint,
      child: m3.SizedBox(
        width: 260,
        child: AppTextField(
          key: const m3.ValueKey('setup-player-name'),
          controller: _controller,
          focusNode: _focus,
          onSubmitted: (_) => _commit(),
        ),
      ),
    );
  }
}

/// The heap cap used when an instance has no override of its own.
class _GlobalMemoryRow extends ConsumerStatefulWidget {
  const _GlobalMemoryRow({required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<_GlobalMemoryRow> createState() => _GlobalMemoryRowState();
}

class _GlobalMemoryRowState extends ConsumerState<_GlobalMemoryRow> {
  /// The value under the pointer during a drag.
  ///
  /// Persisting per pixel of movement would be a disk write per frame; the file
  /// is written once, on release.
  int? _dragging;

  static const _step = 512;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    final value = _dragging ?? widget.settings.memoryMb;

    return _SettingRow(
      label: l10n.setupMemory,
      hint: l10n.setupMemoryHint,
      child: m3.Column(
        crossAxisAlignment: m3.CrossAxisAlignment.stretch,
        children: [
          // The memory number is the answer for this row, so it counts to its new
          // value instead of snapping while the slider is dragged (§3.4). The
          // label is rebuilt per tick so the l10n unit stays in one place.
          AnimatedCount(
            value: value,
            builder: (context, mb) => m3.Text(
              l10n.instanceMemoryMb(mb),
              key: const m3.ValueKey('setup-memory-value'),
              style: AppTheme.body(context),
            ),
          ),
          AppSlider(
            key: const m3.ValueKey('setup-memory'),
            value: clampMemoryMb(value).toDouble(),
            min: kMinMemoryMb.toDouble(),
            max: kMaxMemoryMb.toDouble(),
            divisions: (kMaxMemoryMb - kMinMemoryMb) ~/ _step,
            label: l10n.setupMemory,
            onChanged: (v) =>
                setState(() => _dragging = (v / _step).round() * _step),
            // `onChangeEnd` carries the released value itself, so this reads its
            // argument rather than the `_dragging` field the drag left behind.
            onChangeEnd: (v) {
              final mb = (v / _step).round() * _step;
              setState(() => _dragging = null);
              ref
                  .read(appSettingsProvider.notifier)
                  .set(widget.settings.copyWith(memoryMb: mb));
            },
          ),
          m3.Row(
            children: [
              m3.Icon(
                ShellIcons.warning,
                size: 13,
                color: scheme.onSurfaceVariant,
              ),
              const m3.SizedBox(width: 5),
              m3.Expanded(
                child: m3.Text(
                  l10n.instanceMemoryBigger,
                  style: AppTheme.caption(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
