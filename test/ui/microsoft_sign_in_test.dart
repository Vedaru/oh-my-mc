import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/app/providers.dart';
import 'package:oh_my_mc/core/account/account.dart';
import 'package:oh_my_mc/core/account/microsoft.dart';
import 'package:oh_my_mc/data/account_providers.dart';
import 'package:oh_my_mc/data/account_store.dart';
import 'package:oh_my_mc/data/instance_providers.dart';
import 'package:oh_my_mc/data/instance_store.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/data/microsoft_providers.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/l10n/l10n.dart';
import 'package:oh_my_mc/ui/accounts/accounts_screen.dart';
import 'package:oh_my_mc/ui/theme/app_theme.dart';
import 'package:path/path.dart' as p;

/// The dialog's own behaviour: what it shows, and what it writes.
///
/// The five network calls belong to `test/core/account/microsoft_test.dart`; here the
/// chain is a fake whose poll is held open, because the dialog normally closes the moment
/// the session lands - a test that lets it answer immediately never sees the code.
class _FakeAuth extends MicrosoftAuth {
  _FakeAuth({this.session, this.failure}) : super(clientId: 'configured');

  final MicrosoftSession? session;
  final MicrosoftAuthException? failure;

  /// Completes when the "user" confirms on the Microsoft page.
  final confirmed = Completer<void>();
  var requested = 0;

  @override
  Future<DeviceCode> requestDeviceCode() async {
    requested++;
    return const DeviceCode(
      deviceCode: 'dev',
      userCode: 'K7QP-4XH2M',
      verificationUri: 'https://microsoft.com/link',
      expiresIn: Duration(minutes: 15),
      interval: Duration(seconds: 5),
    );
  }

  @override
  Future<MicrosoftSession> waitForSignIn(
    DeviceCode code, {
    Future<void> Function()? onPending,
    bool Function()? cancelled,
  }) async {
    await confirmed.future;
    final failure = this.failure;
    if (failure != null) throw failure;
    return session!;
  }
}

MicrosoftSession _session() => MicrosoftSession(
  uuid: '11111111-2222-3333-4444-555555555555',
  name: 'Steve',
  accessToken: 'mc-token',
  refreshToken: 'refresh-token',
  expiresAt: DateTime.now().add(const Duration(hours: 23)),
);

void main() {
  late Directory data;

  setUp(() async {
    data = await Directory.systemTemp.createTemp('ms-dialog');
  });

  tearDown(() async {
    if (data.existsSync()) await data.delete(recursive: true);
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required MicrosoftAuth auth,
    String clientId = 'configured',
  }) async {
    tester.view.physicalSize = const Size(1200, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        launcherPathsProvider.overrideWithValue(
          LauncherPaths(data: data, game: Directory(p.join(data.path, 'mc'))),
        ),
        settingsStoreProvider.overrideWith(
          (ref) =>
              MemorySettingsStore(AppSettings(microsoftClientId: clientId)),
        ),
        instanceStoreProvider.overrideWith(
          (ref) => MemoryInstanceStore(const []),
        ),
        accountStoreProvider.overrideWithValue(MemoryAccountStore()),
        microsoftAuthProvider.overrideWithValue(auth),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        // A page needs the shell's Material: a bare screen has no `Material` ancestor
        // and every radio in the account rows asserts.
        child: m3.MaterialApp(
          theme: AppTheme.material(m3.Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const m3.Scaffold(body: AccountsScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return container;
  }

  testWidgets('shows the code, then stores the account it signed in as', (
    tester,
  ) async {
    final auth = _FakeAuth(session: _session());
    final container = await pump(tester, auth: auth);

    await tester.tap(find.byKey(const ValueKey('account-add-microsoft')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The code has to be readable and copyable before anything else matters.
    expect(find.text('K7QP-4XH2M'), findsOneWidget);
    expect(find.text('https://microsoft.com/link'), findsOneWidget);
    expect(auth.requested, 1);

    // The user confirms on the Microsoft page; the dialog closes onto the new account.
    auth.confirmed.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final stored = await tester.runAsync(
      container.read(accountStoreProvider).read,
    );
    expect(stored!.accounts, hasLength(2));
    final microsoft = stored.accounts.firstWhere(
      (account) => account.kind == AccountKind.microsoft,
    );
    expect(microsoft.name, 'Steve');
    expect(microsoft.uuid, '11111111-2222-3333-4444-555555555555');
    expect(microsoft.refreshToken, 'refresh-token');
    // Adding an account is the intent of adding it: it becomes the active one.
    expect(stored.activeId, microsoft.id);
  });

  testWidgets('a failure is reported in the dialog, not thrown at the page', (
    tester,
  ) async {
    final auth = _FakeAuth(
      failure: const MicrosoftAuthException(
        'This Microsoft account does not own Minecraft: Java Edition.',
        code: 'profile_not_found',
      ),
    );
    await pump(tester, auth: auth);

    await tester.tap(find.byKey(const ValueKey('account-add-microsoft')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    auth.confirmed.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('does not own'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with no application id it asks for one instead of failing', (
    tester,
  ) async {
    final auth = _FakeAuth(session: _session());
    await pump(tester, auth: auth, clientId: '');

    await tester.tap(find.byKey(const ValueKey('account-add-microsoft')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('microsoft-client-id')), findsOneWidget);
    // Nothing was asked of Microsoft before an id exists.
    expect(auth.requested, 0);

    await tester.enterText(
      find.byKey(const ValueKey('microsoft-client-id')),
      '00000000-1111-2222-3333-444444444444',
    );
    await tester.tap(find.byKey(const ValueKey('microsoft-client-id-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The id is remembered and the flow continues with it.
    expect(auth.requested, 1);
    expect(find.text('K7QP-4XH2M'), findsOneWidget);
  });
}
