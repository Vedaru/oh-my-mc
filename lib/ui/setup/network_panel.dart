import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../../core/diagnostics/lan_discovery.dart';
import '../../core/diagnostics/network_info.dart';
import '../../core/diagnostics/upnp.dart';
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

  // 联机: worlds this network announced, and the mapping this launcher opened.
  List<LanWorld> _worlds = const [];
  var _scanning = false;
  PortMapping? _mapping;
  var _mappingBusy = false;
  var _scanRan = false;

  Future<void> _findLanWorlds() async {
    setState(() {
      _scanning = true;
      _worlds = const [];
    });
    try {
      final worlds = await ref.read(lanDiscoveryProvider).discover();
      if (!mounted) return;
      setState(() {
        _worlds = worlds;
        _scanRan = true;
      });
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  /// Opens the world's port on the router.
  ///
  /// The port comes from the announcement, not from a setting: the game picks a
  /// random one each session, so asking the user to type it is asking them to read a
  /// chat line correctly.
  Future<void> _openPort(LanWorld world) async {
    final upnp = ref.read(upnpClientProvider);
    setState(() => _mappingBusy = true);
    try {
      final gateway = await upnp.discover();
      if (gateway == null) {
        if (!mounted) return;
        setState(
          () => _progress
            ..clear()
            ..add('no UPnP gateway answered'),
        );
        return;
      }
      final mapping = await upnp.mapPort(
        gateway: gateway,
        internalPort: world.port,
      );
      if (!mounted) return;
      setState(() => _mapping = mapping);
    } finally {
      if (mounted) setState(() => _mappingBusy = false);
    }
  }

  Future<void> _closePort() async {
    final mapping = _mapping;
    if (mapping == null) return;
    final upnp = ref.read(upnpClientProvider);
    setState(() => _mappingBusy = true);
    try {
      final gateway = await upnp.discover();
      if (gateway != null) {
        await upnp.unmapPort(
          gateway: gateway,
          externalPort: mapping.externalPort,
        );
      }
      if (!mounted) return;
      setState(() => _mapping = null);
    } finally {
      if (mounted) setState(() => _mappingBusy = false);
    }
  }

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
                // Bytes alone say nothing about why an install of many small files
                // feels slow: the first-byte time is half that answer.
                ? '${(sample.bytes / 1024).round()} KB · '
                      '${sample.firstByte.inMilliseconds} ms to first byte'
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
        _LanPlay(
          worlds: _worlds,
          scanned: _scanRan,
          scanning: _scanning,
          mapping: _mapping,
          mappingBusy: _mappingBusy,
          onScan: _findLanWorlds,
          onMap: _openPort,
          onUnmap: _closePort,
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

/// 联机: worlds open to LAN on this network, and opening one to the internet.
///
/// Both halves exist because they answer the same question from opposite ends: the
/// scan finds a world someone else opened, the mapping lets a friend outside the
/// house reach yours.
class _LanPlay extends StatelessWidget {
  const _LanPlay({
    required this.worlds,
    required this.scanned,
    required this.scanning,
    required this.mapping,
    required this.mappingBusy,
    required this.onScan,
    required this.onMap,
    required this.onUnmap,
  });

  final List<LanWorld> worlds;

  /// Whether a scan has run: "nothing found" must not appear before the first one.
  final bool scanned;
  final bool scanning;
  final PortMapping? mapping;
  final bool mappingBusy;
  final VoidCallback onScan;
  final void Function(LanWorld world) onMap;
  final VoidCallback onUnmap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;

    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.stretch,
      children: [
        m3.Text(
          l10n.lanHint,
          style: AppTheme.caption(context)
              .copyWith(color: scheme.onSurfaceVariant),
        ),
        const m3.SizedBox(height: 8),
        for (final world in worlds)
          ListRow(
            key: m3.ValueKey('lan-world-${world.shareAddress}'),
            leadingIcon: ShellIcons.network,
            label: world.motd.isEmpty ? l10n.lanUnnamedWorld : world.motd,
            supporting: world.shareAddress,
            supportingMono: true,
            trailingControl: AppButton(
              onPressed: mappingBusy ? null : () => onMap(world),
              style: AppButtonStyle.text,
              size: AppButtonSize.sm,
              label: m3.Text(l10n.lanOpenPort),
            ),
          ),
        if (mapping != null)
          ListRow(
            key: const m3.ValueKey('lan-mapping'),
            leadingIcon: ShellIcons.openExternal,
            label: l10n.lanMappingActive,
            // The external address is the only string a friend outside needs; when
            // the router will not report one, say so instead of showing a wrong one.
            supporting: mapping!.shareAddress ?? l10n.lanNoExternalAddress,
            supportingMono: true,
            trailingControl: AppButton(
              onPressed: mappingBusy ? null : onUnmap,
              style: AppButtonStyle.text,
              size: AppButtonSize.sm,
              label: m3.Text(l10n.lanClosePort),
            ),
          ),
        const m3.SizedBox(height: 8),
        m3.Row(
          children: [
            AppButton(
              key: const m3.ValueKey('lan-scan'),
              onPressed: scanning ? null : onScan,
              style: AppButtonStyle.outlined,
              size: AppButtonSize.sm,
              icon: const m3.Icon(ShellIcons.search, size: 14),
              label: m3.Text(scanning ? l10n.lanScanning : l10n.lanScan),
            ),
          ],
        ),
        if (!scanning && worlds.isEmpty && scanned)
          m3.Padding(
            padding: const m3.EdgeInsets.only(top: 8),
            child: m3.Text(
              l10n.lanNothingFound,
              style: AppTheme.caption(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}
