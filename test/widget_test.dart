import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:criptivo/main.dart';

void main() {
  testWidgets('CriptivoApp builds successfully', (WidgetTester tester) async {
    await tester.pumpWidget(
      const CriptivoApp(home: Scaffold(body: Text('Criptivo test'))),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Criptivo test'), findsOneWidget);
  });
}
