import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fantasy_assistant_app/main.dart';

void main() {
  testWidgets('Muestra el buscador de jugadores', (WidgetTester tester) async {
    await tester.pumpWidget(const FantasyAssistantApp());

    expect(find.text('Fantasy Assistant'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Buscar jugador'), findsOneWidget);
  });
}
