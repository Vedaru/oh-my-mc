import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/settings.dart';
import '../../l10n/l10n.dart';
import '../motion/motion.dart';
import '../shell/shell_icons.dart';
import 'java_panel.dart';

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
    final theme = FluentTheme.of(context);
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);

    return MotionEntrance(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(l10n.navSetup, style: theme.typography.title),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
              const SizedBox(height: 12),
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
                    child: ToggleSwitch(
                      key: const ValueKey('setup-motion'),
                      checked: settings.uiAnimations,
                      // Turning this on cannot override the OS accessibility
                      // setting: MotionScope ORs them.
                      onChanged: notifier.setUiAnimations,
                      content: Text(
                        settings.uiAnimations
                            ? l10n.setupMotionOn
                            : l10n.setupMotionOff,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Section(
                title: l10n.setupLaunch,
                children: [
                  _PlayerNameRow(settings: settings),
                  _GlobalMemoryRow(settings: settings),
                ],
              ),
              const SizedBox(height: 12),
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
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorSecondary,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.resources.dividerStrokeColorDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.typography.bodyStrong),
          const SizedBox(height: 10),
          for (final child in children) ...[child, const SizedBox(height: 10)],
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
    final theme = FluentTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 200,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(label, style: theme.typography.body),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  hint,
                  style: theme.typography.caption?.copyWith(
                    color: theme.inactiveColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
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
    return RadioGroup<T>(
      groupValue: value,
      onChanged: (selected) {
        if (selected != null) onChanged(selected);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in options.entries)
            RadioButton<T>(
              key: ValueKey('$keyPrefix-${entry.key}'),
              value: entry.key,
              content: Text(entry.value),
            ),
        ],
      ),
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
      child: SizedBox(
        width: 220,
        child: TextBox(
          key: const ValueKey('setup-player-name'),
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

  static const _minMb = 512;
  static const _maxMb = 16384;
  static const _step = 512;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = FluentTheme.of(context);
    final value = _dragging ?? widget.settings.memoryMb;

    return _SettingRow(
      label: l10n.setupMemory,
      hint: l10n.setupMemoryHint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.instanceMemoryMb(value), style: theme.typography.body),
          Slider(
            key: const ValueKey('setup-memory'),
            value: value.clamp(_minMb, _maxMb).toDouble(),
            min: _minMb.toDouble(),
            max: _maxMb.toDouble(),
            divisions: (_maxMb - _minMb) ~/ _step,
            onChanged: (v) =>
                setState(() => _dragging = (v / _step).round() * _step),
            onChangeEnd: (v) {
              final mb = (v / _step).round() * _step;
              setState(() => _dragging = null);
              ref
                  .read(appSettingsProvider.notifier)
                  .set(widget.settings.copyWith(memoryMb: mb));
            },
          ),
          Row(
            children: [
              Icon(ShellIcons.warning, size: 12, color: theme.inactiveColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  l10n.instanceMemoryBigger,
                  style: theme.typography.caption?.copyWith(
                    color: theme.inactiveColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
