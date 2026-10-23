import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/update/launcher_update.dart';

/// The launcher's own update check has one job: say "there is a newer release" without
/// ever turning a network problem into a banner.
void main() {
  test('versions compare as numbers, not as strings', () {
    // The bug a string comparison causes: "0.9.0" > "0.10.0" lexicographically.
    expect(LauncherUpdate.isNewer('0.10.1', '0.9.9'), isTrue);
    expect(LauncherUpdate.isNewer('0.9.9', '0.10.1'), isFalse);
    expect(LauncherUpdate.isNewer('1.0.0', '0.99.99'), isTrue);
    expect(LauncherUpdate.isNewer('0.1.0', '0.1.0'), isFalse);
    expect(LauncherUpdate.isNewer('0.1.1', '0.1.0'), isTrue);
  });

  test('a build suffix does not affect the comparison', () {
    expect(LauncherUpdate.isNewer('0.2.0+7', '0.1.0+3'), isTrue);
    expect(LauncherUpdate.isNewer('0.2.0-beta.1', '0.1.0'), isTrue);
    // A pre-release of the *same* version is not newer than the release.
    expect(LauncherUpdate.isNewer('0.2.0-beta.1', '0.2.0'), isFalse);
  });

  test('a release JSON becomes an update, minus the v', () {
    final update = LauncherUpdateChecker.parse({
      'tag_name': 'v0.3.0',
      'html_url': 'https://github.com/Vedaru/oh-my-mc/releases/tag/v0.3.0',
      'body': 'notes',
    }, currentVersion: '0.1.0');

    expect(update, isNotNull);
    expect(update!.version, '0.3.0');
    expect(update.url, contains('/releases/tag/v0.3.0'));
    expect(update.notes, 'notes');
  });

  test('the current release is not an update', () {
    expect(
      LauncherUpdateChecker.parse({
        'tag_name': 'v0.1.0',
        'html_url': 'https://example.invalid',
      }, currentVersion: '0.1.0'),
      isNull,
    );
  });

  test('a malformed answer is not an update', () {
    // GitHub answers 200 with a message body when the repository has no releases.
    expect(
      LauncherUpdateChecker.parse({
        'message': 'Not Found',
      }, currentVersion: '0.1.0'),
      isNull,
    );
  });
}
