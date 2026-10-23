import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../../core/diagnostics/lan_discovery.dart';
import '../../core/diagnostics/network_info.dart';
import '../../core/diagnostics/upnp.dart';
import '../../data/diagnostics_providers.dart';
import '../../l10n/l10n.dart';
import '../components/app_button.dart';
import '../components/list_row.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';

/// 联机: worlds open to LAN on this network, and opening one to the internet.
///
/// Both halves exist because they answer the same question from opposite ends: the scan
/// finds a world someone else opened, the mapping lets a friend outside the house reach
/// yours. It lives on its own page rather than in 设置 → 网络, because it is something you
/// do while playing, not something you configure once.
class LanPanel extends ConsumerStatefulWidget {
  const LanPanel({super.key});

  @override
  ConsumerState<LanPanel> createState() => _LanPanelState();
}

class _LanPanelState extends ConsumerState<LanPanel> {
  List<LanWorld> _worlds = const [];
  var _scanning = false;
  PortMapping? _mapping;
  var _mappingBusy = false;
  var _scanRan = false;

  /// The last thing the router said, when it said no. A UPnP failure is a network
  /// problem, not a launcher bug, so it is reported in place rather than thrown.
  String? _error;

  Future<void> _findLanWorlds() async {
    setState(() {
      _scanning = true;
      _worlds = const [];
      _error = null;
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
  /// The port comes from the announcement, not from a setting: the game picks a random
  /// one each session, so asking the user to type it is asking them to read a chat line
  /// correctly.
  Future<void> _openPort(LanWorld world) async {
    final upnp = ref.read(upnpClientProvider);
    setState(() => _mappingBusy = true);
    try {
      final gateway = await upnp.discover();
      if (gateway == null) {
        if (!mounted) return;
        setState(() => _error = context.l10n.lanNoGateway);
        return;
      }
      final mapping = await upnp.mapPort(
        gateway: gateway,
        internalPort: world.port,
      );
      if (!mounted) return;
      setState(() {
        _mapping = mapping;
        _error = null;
      });
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    // Reading interfaces happens once per build dependency, not per frame: the provider
    // caches it and a failure is a null address rather than an error card.
    final interfaces = ref.watch(lanInterfacesProvider).value;
    final lan = interfaces == null ? null : preferredLanAddress(interfaces);

    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.stretch,
      children: [
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
        m3.Text(
          l10n.lanHint,
          style: AppTheme.caption(context)
              .copyWith(color: scheme.onSurfaceVariant),
        ),
        const m3.SizedBox(height: 8),
        for (final world in _worlds)
          ListRow(
            key: m3.ValueKey('lan-world-${world.shareAddress}'),
            leadingIcon: ShellIcons.network,
            label: world.motd.isEmpty ? l10n.lanUnnamedWorld : world.motd,
            supporting: world.shareAddress,
            supportingMono: true,
            trailingControl: AppButton(
              onPressed: _mappingBusy ? null : () => _openPort(world),
              style: AppButtonStyle.text,
              size: AppButtonSize.sm,
              label: m3.Text(l10n.lanOpenPort),
            ),
          ),
        if (_mapping != null)
          ListRow(
            key: const m3.ValueKey('lan-mapping'),
            leadingIcon: ShellIcons.openExternal,
            label: l10n.lanMappingActive,
            // The external address is the only string a friend outside needs; when the
            // router will not report one, say so instead of showing a wrong one.
            supporting: _mapping!.shareAddress ?? l10n.lanNoExternalAddress,
            supportingMono: true,
            trailingControl: AppButton(
              onPressed: _mappingBusy ? null : _closePort,
              style: AppButtonStyle.text,
              size: AppButtonSize.sm,
              label: m3.Text(l10n.lanClosePort),
            ),
          ),
        if (_error != null)
          m3.Padding(
            padding: const m3.EdgeInsets.only(top: 8),
            child: m3.Text(
              _error!,
              style: AppTheme.caption(context).copyWith(color: scheme.error),
            ),
          ),
        const m3.SizedBox(height: 8),
        m3.Row(
          children: [
            AppButton(
              key: const m3.ValueKey('lan-scan'),
              onPressed: _scanning ? null : _findLanWorlds,
              style: AppButtonStyle.outlined,
              size: AppButtonSize.sm,
              icon: const m3.Icon(ShellIcons.search, size: 14),
              label: m3.Text(_scanning ? l10n.lanScanning : l10n.lanScan),
            ),
          ],
        ),
        if (!_scanning && !_scanRan)
          m3.Padding(
            padding: const m3.EdgeInsets.only(top: 8),
            child: m3.Text(
              // Before any scan the page would otherwise be one button and a lot of
              // nothing; the game side of the ritual is the part people miss.
              l10n.lanNeverScanned,
              style: AppTheme.caption(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        if (!_scanning && _worlds.isEmpty && _scanRan)
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
