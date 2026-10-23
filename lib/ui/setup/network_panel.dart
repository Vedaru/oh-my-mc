import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../../core/diagnostics/network_info.dart';
import '../../core/diagnostics/speed_test.dart';
import '../../app/providers.dart';
import '../../data/diagnostics_providers.dart';
import '../../data/settings.dart';
import '../../l10n/l10n.dart';
import '../components/app_button.dart';
import '../components/app_radio_group.dart';
import '../components/list_row.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';

/// 设置 → 网络: what the launcher can measure about the network, and the address to
/// share for LAN play.
///
/// Two rows, not a dashboard: a speed number nobody can act on is decoration, and
/// the LAN address has exactly one use.
class NetworkPanel extends ConsumerStatefulWidget {
  const NetworkPanel({super.key});

  @override
  ConsumerState<NetworkPanel> createState() => _NetworkPanelState();
}

class _NetworkPanelState extends ConsumerState<NetworkPanel> {
  List<SpeedSample> _samples = const [];
  var _running = false;
  final _progress = <String>[];

  Future<void> _runTest() async {
    final test = ref.read(speedTestProvider);
    setState(() {
      _running = true;
      _samples = const [];
      _progress.clear();
    });
    try {
      final samples = await test.run(
        Mirror.defaults,
        onSample: (sample) {
          if (!mounted) return;
          // Results appear as they arrive: the first mirror is usually fast and the
          // user should not stare at a spinner to see it.
          setState(() => _samples = [..._samples, sample]);
        },
      );
      if (!mounted) return;
      // The winner is remembered, not applied by itself: `auto` follows it, and a
      // user who pinned a source keeps their pin.
      final fastest = _fastestOf(samples);
      if (fastest != null) {
        await ref
            .read(appSettingsProvider.notifier)
            .set(
              ref.read(appSettingsProvider).copyWith(fastestSource: fastest),
            );
      }
      if (!mounted) return;
      setState(() {
        _samples = samples;
        _running = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _progress
          ..clear()
          ..add('$e');
        _running = false;
      });
    }
  }

  /// The source with the highest measured throughput, if any sample succeeded.
  static String? _fastestOf(List<SpeedSample> samples) {
    final ok = [
      for (final sample in samples)
        if (sample.ok) sample,
    ]..sort((a, b) => b.bytesPerSecond.compareTo(a.bytesPerSecond));
    if (ok.isEmpty) return null;
    return switch (ok.first.name) {
      'Mojang' => 'official',
      'BMCLAPI' => 'bmclapi',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    // Reading interfaces happens once per build dependency, not per frame: the
    // provider caches it and a failure is a null address rather than an error card.
    final interfaces = ref.watch(lanInterfacesProvider).value;
    final lan = interfaces == null ? null : preferredLanAddress(interfaces);

    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.stretch,
      children: [
        m3.Text(
          l10n.settingsNetworkHint,
          style: AppTheme.caption(context)
              .copyWith(color: scheme.onSurfaceVariant),
        ),
        const m3.SizedBox(height: 8),
        for (final sample in _samples)
          ListRow(
            key: m3.ValueKey('speed-${sample.name}'),
            leadingIcon: ShellIcons.download,
            label: sample.name,
            supporting: sample.ok
                ? '${(sample.bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
                : sample.url,
            // The number goes in the trailing slot; a failure replaces the
            // supporting line instead, so the reason appears once.
            trailingText: sample.ok ? sample.label : null,
            errorText: sample.ok ? null : sample.label,
          ),
        for (final line in _progress)
          m3.Text(line, style: AppTheme.caption(context)),
        const m3.SizedBox(height: 8),
        m3.Row(
          children: [
            AppButton(
              key: const m3.ValueKey('speed-test'),
              onPressed: _running ? null : _runTest,
              style: AppButtonStyle.outlined,
              size: AppButtonSize.sm,
              icon: const m3.Icon(ShellIcons.download, size: 14),
              label: m3.Text(
                _running ? l10n.settingsSpeedTesting : l10n.settingsSpeedTest,
              ),
            ),
          ],
        ),
        const m3.SizedBox(height: 14),
        // The LAN address: one line, copyable, with the interface it came from so a
        // wrong pick (VPN, Docker) is at least visible.
        ListRow(
          key: const m3.ValueKey('lan-address'),
          leadingIcon: ShellIcons.network,
          label: l10n.settingsLanAddress,
          supporting: interfaces == null
              ? '…'
              : lan == null
              ? l10n.settingsLanUnknown
              : '${lan.address} · ${lan.interfaceName}',
          supportingMono: lan != null,
          trailingControl: lan == null
              ? null
              : AppButton(
                  key: const m3.ValueKey('lan-copy'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: lan.address));
                    if (!context.mounted) return;
                    m3.ScaffoldMessenger.maybeOf(context)
                      ?..hideCurrentSnackBar()
                      ..showSnackBar(
                        m3.SnackBar(
                          content: m3.Text(l10n.settingsCopied),
                          behavior: m3.SnackBarBehavior.floating,
                          width: 160,
                        ),
                      );
                  },
                  style: AppButtonStyle.text,
                  size: AppButtonSize.sm,
                  label: m3.Text(l10n.settingsCopy),
                ),
        ),
        const m3.SizedBox(height: 14),
        // Which source installs use. `auto` is not a third choice between the two:
        // it means "whichever the last test found faster", which is what most users
        // actually want and what the test above produces.
        AppRadioGroup<SourcePreference>(
          keyPrefix: 'source',
          value: ref.watch(appSettingsProvider).downloadSource,
          onChanged: (value) => ref
              .read(appSettingsProvider.notifier)
              .set(
                ref.read(appSettingsProvider).copyWith(downloadSource: value),
              ),
          options: {
            SourcePreference.auto: l10n.sourceAuto(
              ref.watch(appSettingsProvider).fastestSource == 'bmclapi'
                  ? 'BMCLAPI'
                  : 'Mojang',
            ),
            SourcePreference.official: l10n.sourceOfficial,
            SourcePreference.bmclapi: l10n.sourceBmclapi,
          },
        ),
      ],
    );
  }
}
