import 'package:material_ui/material_ui.dart';

/// Bootstrap placeholder. The Fluent shell, theme, motion and routing land in
/// M3 (docs/PLAN-M1-M4.md); M1/M2 build the Flutter-free engine underneath.
void main() {
  runApp(const OhMyMcApp());
}

class OhMyMcApp extends StatelessWidget {
  const OhMyMcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'oh my mc',
      home: Scaffold(body: Center(child: Text('oh my mc'))),
    );
  }
}
