import 'package:diting_shared/ui/navigator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('CardPageRoute pushes and pops its page without exceptions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(
                  CardPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('detail')),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);

    Navigator.of(tester.element(find.text('detail'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
