/// The launcher's own version.
///
/// A constant rather than a `pubspec.yaml` read: the release build has no pubspec on
/// disk. `test/app/version_test.dart` compares it with `pubspec.yaml`, so the two
/// cannot drift without a failing test.
const appVersion = '0.1.0';
