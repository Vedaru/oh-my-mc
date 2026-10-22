import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/app/providers.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/l10n/l10n.dart';
import 'package:oh_my_mc/main.dart';

/// Pumps the real app root, so a missing delegate or a type mismatch between the
/// two localization trees fails here rather than in the first frame a user sees.
Future<void> _pumpApp(WidgetTester tester, {Locale? locale}) async {
  await tester.pumpWidget(OhMyMcApp(locale: locale));
  await tester.pumpAndSettle();
}

/// Switches language the way `/setup` does: through the settings notifier.
///
/// Re-pumping with a different `locale:` argument no longer works by design -
/// the store is the source of truth and is read once, at provider build - and a
/// test that could still switch via the constructor would be testing a mechanism
/// no user can reach.
Future<void> _setLanguage(
  WidgetTester tester,
  LanguagePreference language,
) async {
  final context = tester.element(find.byType(m3.NavigationRail).first);
  await ProviderScope.containerOf(context)
      .read(appSettingsProvider.notifier)
      .setLanguage(language);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the app resolves English and shows it', (tester) async {
    await _pumpApp(tester, locale: const Locale('en'));
    expect(find.text('oh my mc'), findsOneWidget);
  });

  testWidgets('the app resolves Chinese and the widget tree is localized', (
    tester,
  ) async {
    await _pumpApp(tester, locale: const Locale('zh'));

    // appTitle is deliberately identical in both languages, so assert on a
    // string that must differ. Reading it through the same BuildContext the app
    // built with proves AppLocalizations is genuinely in scope for widgets, not
    // merely loadable from the delegate.
    final context = tester.element(find.byType(m3.NavigationRail).first);
    expect(context.l10n.navLaunch, '启动');
    expect(context.l10n.setupLanguage, '语言');
    expect(AppLocalizations.of(context).localeName, 'zh');
  });

  testWidgets('switching locale at runtime relocalizes the same tree', (
    tester,
  ) async {
    await _pumpApp(tester, locale: const Locale('en'));
    expect(
      tester.element(find.byType(m3.NavigationRail).first).l10n.navLaunch,
      'Launch',
    );

    await _setLanguage(tester, LanguagePreference.chinese);
    expect(
      tester.element(find.byType(m3.NavigationRail).first).l10n.navLaunch,
      '启动',
      reason: 'a language change must relocalize without a restart',
    );
  });

  testWidgets('plural and placeholder messages resolve in both languages', (
    tester,
  ) async {
    await _pumpApp(tester, locale: const Locale('en'));
    final en = tester.element(find.byType(m3.NavigationRail).first).l10n;
    expect(en.instanceCount(0), 'No instances');
    expect(en.instanceCount(1), '1 instance');
    expect(en.instanceCount(4), '4 instances');
    expect(
      en.instanceDeleteConfirm('1.20.4'),
      'Delete 1.20.4? This cannot be undone.',
    );

    await _setLanguage(tester, LanguagePreference.chinese);
    final zh = tester.element(find.byType(m3.NavigationRail).first).l10n;
    expect(zh.instanceCount(0), '暂无实例');
    expect(zh.instanceCount(4), '4 个实例');
    expect(zh.instanceDeleteConfirm('1.20.4'), '删除 1.20.4？此操作无法撤销。');
  });
}
