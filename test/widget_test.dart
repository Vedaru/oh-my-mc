import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/main.dart';

void main() {
  testWidgets('bootstrap renders', (tester) async {
    await tester.pumpWidget(const OhMyMcApp());
    // The shell is up: a rail with the five destinations (and the header title).
    expect(find.text('Launch'), findsWidgets);
  });
}
