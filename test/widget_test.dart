import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:criptivo/main.dart';

void main() {
  testWidgets('CriptivoApp builds and shows AuthGate', (
    WidgetTester tester,
  ) async {
    // Подаваме приложението
    await tester.pumpWidget(const CriptivoApp());

    // Изчакваме първия frame
    await tester.pump();

    // Приложението трябва да се построи без грешка
    expect(find.byType(MaterialApp), findsOneWidget);

    // AuthGate е home widget-ът
    expect(find.byType(AuthGate), findsOneWidget);
  });
}
