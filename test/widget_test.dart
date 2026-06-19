import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbook_lottery/main.dart';

void main() {
  testWidgets('opens the login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('User Name'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });
}
