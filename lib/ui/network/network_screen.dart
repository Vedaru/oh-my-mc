import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../../l10n/l10n.dart';
import '../components/page_body.dart';
import 'lan_panel.dart';

/// 联机: the LAN scan and the port mapping, as a destination of their own.
///
/// These started inside 设置 → 网络, next to the speed test, which is where a *setting*
/// belongs. Joining a friend is not a setting: it is something you do while playing, and
/// two clicks inside 设置 is why nobody found it.
class NetworkScreen extends ConsumerWidget {
  const NetworkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PageBody(
      child: m3.Column(
        crossAxisAlignment: m3.CrossAxisAlignment.stretch,
        children: [PageTitle(context.l10n.navNetwork), const LanPanel()],
      ),
    );
  }
}
