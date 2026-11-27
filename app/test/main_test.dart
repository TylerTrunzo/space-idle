import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/main.dart' as app;
import 'package:space_idle/theme.dart';

void main() {
  testWidgets('main boots a themed app titled Space Idle', (tester) async {
    app.main();
    await tester.pump();

    final material = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(material.title, 'Space Idle');
    expect(material.theme?.scaffoldBackgroundColor, Palette.background);
    expect(find.text('Space Idle'), findsOneWidget);
  });
}
