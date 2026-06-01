// This is a basic Flutter widget test for SmartMatchingApp.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';

void main() {
  testWidgets('SmartMatchingApp smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SmartMatchingApp());

    // Verify that the AuthGate displays the initial loading indicator
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Settle the delayed auth gate futures/timers
    await tester.pump(const Duration(milliseconds: 600));
  });
}
