import 'package:diting_shared/ui/prism_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('PrismListView builds and scrolls rows it has not laid out', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrismListView(
            itemCount: 1000,
            estimatedItemExtent: 48,
            itemBuilder: (context, index) =>
                SizedBox(height: 48, child: Text('row $index')),
          ),
        ),
      ),
    );

    expect(find.text('row 0'), findsOneWidget);

    await tester.drag(find.byType(PrismListView), const Offset(0, -4800));
    await tester.pumpAndSettle();

    expect(find.text('row 0'), findsNothing);
  });

  testWidgets('itemExtent builds a fixed-extent list', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrismListView(
            itemCount: 500,
            itemExtent: 40,
            itemBuilder: (context, index) =>
                SizedBox(height: 40, child: Text('row $index')),
          ),
        ),
      ),
    );

    expect(find.text('row 0'), findsOneWidget);
    await tester.drag(find.byType(PrismListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('row 0'), findsNothing);
  });
}
