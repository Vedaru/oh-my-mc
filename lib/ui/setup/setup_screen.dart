import 'dart:io';

import 'dart:ui' show PlatformDispatcher;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../../app/providers.dart';
import '../../core/instance/memory.dart';
import '../../data/settings.dart';
import '../../l10n/l10n.dart';
import '../motion/motion.dart';
import '../components/section_drawer.dart';
import '../components/section_page.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';
import 'java_panel.dart';
import 'about_panel.dart';
import 'network_panel.dart';
import '../components/app_accent_picker.dart';
import '../components/app_button.dart';
import '../components/app_radio_group.dart';
import '../components/app_slider.dart';
import '../components/app_text_field.dart';

/// The settings screen: a section list on the left, one section on the right.
///
/// It used to be one page with six groups stacked on it - language, appearance,
/// launch, Java, network, about - which by the end was a scroll long enough that
/// finding the memory slider meant hunting. A launcher's settings are looked up, not
/// read, so the sections are a **list you pick from**, and only one is on screen.
///
/// Each control still writes through [AppSettingsNotifier] immediately: no Save button,
/// no unsaved state.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

/// The sections, in the order they appear in the list.
enum SetupSection { general, appearance, launch, java, network, about }

class _SetupScreenState extends ConsumerState<SetupScreen> {
  var _section = SetupSection.general;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SectionPage(
      // Same frame as an instance's page: heading, section list, one section. The
      // list stays put while the section scrolls, which is what keeps "where am I"
      // answerable on a short window.
      title: l10n.navSetup,
      mark: m3.Icon(
        ShellIcons.settings,
        size: 22,
        color: m3.Theme.of(context).colorScheme.primary,
      ),
      selectedIndex: _section.index,
      onSelected: (index) =>
          setState(() => _section = SetupSection.values[index]),
      destinations: [
        for (final section in SetupSection.values) _destination(l10n, section),
      ],
      bodyScrollable: true,
      body: m3.KeyedSubtree(
        // Keyed by section so switching starts at the top instead of inheriting the
        // previous section's scroll offset.
        key: m3.ValueKey('setup-${_section.name}'),
        child: MotionEntrance(children: [_body(context, _section)]),
      ),
    );
  }

  /// The language the OS would pick, as a name the user recognises.
  String _systemLanguage(AppLocalizations l10n) {
    final code = PlatformDispatcher.instance.locale.languageCode;
    return switch (code) {
      'zh' => l10n.languageChinese,
      'en' => l10n.languageEnglish,
      _ => code,
    };
  }

  SectionDestination _destination(
    AppLocalizations l10n,
    SetupSection section,
  ) => switch (section) {
    SetupSection.general => SectionDestination(
      key: 'setup-section-general',
      label: l10n.setupSectionGeneral,
      icon: ShellIcons.settings,
    ),
    SetupSection.appearance => SectionDestination(
      key: 'setup-section-appearance',
      label: l10n.setupSectionAppearance,
      icon: ShellIcons.resourcePacks,
    ),
    SetupSection.launch => SectionDestination(
      key: 'setup-section-launch',
      label: l10n.setupLaunch,
      icon: ShellIcons.play,
    ),
    SetupSection.java => SectionDestination(
      key: 'setup-section-java',
      label: l10n.setupJava,
      icon: ShellIcons.java,
    ),
    SetupSection.network => SectionDestination(
      key: 'setup-section-network',
      label: l10n.settingsNetworkTitle,
      icon: ShellIcons.network,
    ),
    SetupSection.about => SectionDestination(
      key: 'setup-section-about',
      label: l10n.aboutTitle,
      icon: ShellIcons.info,
    ),
  };

  Widget _body(BuildContext context, SetupSection section) {
    final l10n = context.l10n;
    // `watch`, not `read`: a control that writes a setting has to be redrawn from the
    // new value, and reading the provider only once is how the radio group used to
    // keep showing the option the user had already left.
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);

    return switch (section) {
      SetupSection.general => _Section(
        title: l10n.setupLanguage,
        children: [
          _SettingRow(
            label: l10n.setupLanguage,
            hint: l10n.setupLanguageHint,
            child: _Choice<LanguagePreference>(
              keyPrefix: 'language',
              value: settings.language,
              options: {
                // Naming what the OS resolves to turns "Follow system" from a choice
                // that looks like it did nothing into a choice that says what it is:
                // on an English machine it reads "Follow system (English)", which is
                // why picking it changes no text.
                LanguagePreference.system: l10n.languageSystemWith(
                  _systemLanguage(l10n),
                ),
                LanguagePreference.english: l10n.languageEnglish,
                LanguagePreference.chinese: l10n.languageChinese,
              },
              onChanged: notifier.setLanguage,
            ),
          ),
        ],
      ),
      SetupSection.appearance => _Section(
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
          // No animation switch: motion is part of the design, and only the OS
          // accessibility flag can turn it off (`MotionScope` ORs it in).
          _SettingRow(
            label: l10n.setupAccent,
            hint: l10n.setupAccentHint,
            child: AppAccentPicker(
              value: settings.accent,
              onChanged: notifier.setAccent,
            ),
          ),
          _SettingRow(
            label: l10n.setupBackground,
            hint: l10n.setupBackgroundHint,
            child: _BackgroundPicker(
              path: settings.backgroundPath,
              onPicked: (path) => notifier.setBackground(path),
            ),
          ),
        ],
      ),
      SetupSection.launch => _Section(
        title: l10n.setupLaunch,
        children: [
          _PlayerNameRow(settings: settings),
          _GlobalMemoryRow(settings: settings),
        ],
      ),
      SetupSection.java => _Section(
        title: l10n.setupJava,
        children: const [JavaRuntimeList()],
      ),
      SetupSection.network => _Section(
        title: l10n.settingsNetworkTitle,
        children: const [NetworkPanel()],
      ),
      SetupSection.about => _Section(
        title: l10n.aboutTitle,
        children: const [AboutPanel()],
      ),
    };
  }
}

/// A titled group of settings.
///
/// One filled surface per group, MD3's `surfaceContainerLow` at a 16 px radius
/// with no outline: the border this used to carry drew a box around every group,
/// which on a dark theme read as six unrelated panels rather than one page.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = m3.Theme.of(context).colorScheme;
    return m3.Container(
      padding: const m3.EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: m3.BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: m3.BorderRadius.circular(16),
      ),
      child: m3.Column(
        crossAxisAlignment: m3.CrossAxisAlignment.stretch,
        children: [
          m3.Text(
            title,
            style: AppTheme.title(context).copyWith(color: scheme.onSurface),
          ),
          const m3.SizedBox(height: 16),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const m3.SizedBox(height: 16),
            children[i],
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
          width: 180,
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

/// Picks the wallpaper, and shows which one is in use.
///
/// The preview is the point: a path in a text field tells a user nothing about the
/// picture they are about to put behind every page.
class _BackgroundPicker extends StatelessWidget {
  const _BackgroundPicker({required this.path, required this.onPicked});

  final String? path;
  final void Function(String? path) onPicked;

  Future<void> _pick(BuildContext context) async {
    final l10n = context.l10n;
    final messenger = m3.ScaffoldMessenger.maybeOf(context);
    final picked = await FilePicker.pickFiles(
      dialogTitle: l10n.setupBackgroundPick,
      type: FileType.image,
    );
    final chosen = picked.isEmpty ? null : picked.first.path;
    if (chosen == null) return;
    // Verify before storing: a path that cannot be decoded would paint nothing, and
    // "nothing" is exactly what the user did not ask for.
    try {
      // Decodes at least the header: a text file renamed to .png is refused here
      // rather than behind every page.
      await decodeImageFromList(await File(chosen).readAsBytes());
    } on Object {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          m3.SnackBar(
            content: m3.Text(l10n.setupBackgroundFailed),
            behavior: m3.SnackBarBehavior.floating,
          ),
        );
      return;
    }
    onPicked(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    final path = this.path;

    return m3.Row(
      children: [
        if (path != null) ...[
          m3.ClipRRect(
            borderRadius: m3.BorderRadius.circular(8),
            child: m3.Image.file(
              File(path),
              width: 64,
              height: 40,
              fit: m3.BoxFit.cover,
              errorBuilder: (context, error, stack) => m3.Container(
                width: 64,
                height: 40,
                color: scheme.surfaceContainerHighest,
                child: m3.Icon(
                  ShellIcons.warning,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const m3.SizedBox(width: 12),
        ],
        AppButton(
          key: const m3.ValueKey('background-pick'),
          onPressed: () => _pick(context),
          style: AppButtonStyle.outlined,
          size: AppButtonSize.sm,
          icon: const m3.Icon(ShellIcons.folder, size: 14),
          label: m3.Text(l10n.setupBackgroundPick),
        ),
        if (path != null) ...[
          const m3.SizedBox(width: 8),
          AppButton(
            key: const m3.ValueKey('background-clear'),
            onPressed: () => onPicked(null),
            style: AppButtonStyle.text,
            size: AppButtonSize.sm,
            label: m3.Text(l10n.setupBackgroundClear),
          ),
        ],
      ],
    );
  }
}
