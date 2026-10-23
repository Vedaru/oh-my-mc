import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/core/mods/mc_target.dart';

void main() {
  test('vanilla ids are game versions with no loader', () {
    final target = McTarget.fromVersionId('1.20.1');
    expect(target?.gameVersion, '1.20.1');
    expect(target?.loader, isNull);
    expect(target?.isModded, isFalse);
  });

  test('fabric and quilt ids split the game version off the end', () {
    expect(
      McTarget.fromVersionId('fabric-loader-0.16.9-1.20.1')?.gameVersion,
      '1.20.1',
    );
    expect(
      McTarget.fromVersionId('fabric-loader-0.16.9-1.20.1')?.loader,
      'fabric',
    );
    // A snapshot has no dot-dash ambiguity, but the loader version does.
    expect(
      McTarget.fromVersionId('quilt-loader-0.24.0-24w14a')?.gameVersion,
      '24w14a',
    );
  });

  test('forge keeps the game version in front', () {
    final target = McTarget.fromVersionId('1.20.1-forge-47.4.28');
    expect(target?.gameVersion, '1.20.1');
    expect(target?.loader, 'forge');
  });

  test('neoforge derives the game version from its own numbering', () {
    // NeoForge <major>.<minor> tracks MC 1.<major>.<minor>; minor 0 means no patch
    // release, which is 1.<major>.
    expect(McTarget.fromVersionId('neoforge-21.1.264')?.gameVersion, '1.21.1');
    expect(McTarget.fromVersionId('neoforge-20.4.237')?.gameVersion, '1.20.4');
    expect(McTarget.fromVersionId('neoforge-21.0.167')?.gameVersion, '1.21');
    expect(McTarget.fromVersionId('neoforge-21.1.264')?.loader, 'neoforge');
  });

  test('snapshots and pre-releases are vanilla, not garbage', () {
    expect(McTarget.fromVersionId('24w14a')?.gameVersion, '24w14a');
    expect(McTarget.fromVersionId('1.21.2-pre1')?.gameVersion, '1.21.2-pre1');
  });

  test('an id it does not understand is null rather than a wrong guess', () {
    expect(McTarget.fromVersionId(''), isNull);
    expect(McTarget.fromVersionId('my-custom-thing'), isNull);
  });

  test('an instance reports its own loader, not the one in its id', () {
    // An instance's versionId is the game version; the loader is a separate field.
    // Reading only the id made every Fabric instance look vanilla, which is why the
    // mod search refused to open for it.
    const fabric = Instance(
      id: 'a',
      name: 'A',
      versionId: '1.20.1',
      loader: LoaderKind.fabric,
      loaderVersion: '0.16.9',
    );
    final target = McTarget.fromInstance(fabric);

    expect(target?.loader, 'fabric');
    expect(target?.gameVersion, '1.20.1');
    expect(target?.isModded, isTrue);
  });

  test('a vanilla instance stays unmodded', () {
    const vanilla = Instance(id: 'b', name: 'B', versionId: '1.20.1');

    expect(McTarget.fromInstance(vanilla)?.isModded, isFalse);
  });
}
