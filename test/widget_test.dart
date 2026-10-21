import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/main.dart';

void main() {
  testWidgets('bootstrap renders', (tester) async {
    await tester.pumpWidget(const OhMyMcApp());
    expect(find.text('oh my mc'), findsWidgets);
  });
}
