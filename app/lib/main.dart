import 'package:material_ui/material_ui.dart';
import 'package:space_idle/theme.dart';

/// Starts the app.
///
/// A placeholder shell until the game controller and star map land in later
/// stage 2 tasks.
void main() {
  runApp(
    MaterialApp(
      title: 'Space Idle',
      theme: buildTheme(),
      home: const Scaffold(body: Center(child: Text('Space Idle'))),
    ),
  );
}
