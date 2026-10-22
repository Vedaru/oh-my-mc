import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/core/launch/launch_handle.dart';
import 'package:oh_my_mc/data/launch_providers.dart';
import 'package:oh_my_mc/ui/instances/instances_screen.dart';

/// A card's destination follows the live session, not the selection.
///
/// The selection is invisible again (the grid no longer outlines it), so the
/// only state a click can act on is "this instance is running". These cases pin
/// that, including the one that made settings a dead end: the run view has to
/// stay reachable while a session is alive.
void main() {
  const mine = Instance(id: 'a', name: 'A', versionId: '1.20.1');
  const other = Instance(id: 'b', name: 'B', versionId: '1.20.1');

  LaunchSession session(LaunchState state, String? instanceId) =>
      LaunchSession(state: state, log: const [], instanceId: instanceId);

  test('the running instance leads back to the run view', () {
    final running = session(LaunchState.running, mine.id);

    expect(instanceTargetFor(running, mine), InstanceTarget.run);
    expect(
      instanceTargetFor(running, other),
      InstanceTarget.settings,
      reason: 'one running session must not redirect every card',
    );
  });

  test('every card leads to its settings when nothing is running', () {
    expect(
      instanceTargetFor(const LaunchSession.idle(), mine),
      InstanceTarget.settings,
    );
    expect(
      instanceTargetFor(const LaunchSession.idle(), other),
      InstanceTarget.settings,
    );
  });

  test('an ended session leaves the run view behind', () {
    expect(
      instanceTargetFor(session(LaunchState.exited, mine.id), mine),
      InstanceTarget.settings,
    );
  });
}
