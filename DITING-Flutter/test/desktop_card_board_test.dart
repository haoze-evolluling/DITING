import 'package:diting/desktop/widgets/desktop_card_board.dart';
import 'package:diting/desktop/widgets/masonry_grid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pumpBoard(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DesktopCardBoard(
              cards: const [
                SizedBox(key: ValueKey('short'), height: 40),
                SizedBox(key: ValueKey('tall'), height: 160),
                SizedBox(key: ValueKey('medium'), height: 90),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('内容宽度达到 760 后两列瀑布流，每张卡片只占一列', (tester) async {
    await pumpBoard(tester, 1000);

    expect(find.byType(MasonryGrid), findsOneWidget);
    final boxes = [
      for (final key in ['short', 'tall', 'medium'])
        tester.renderObject<RenderBox>(find.byKey(ValueKey(key))),
    ];
    final widths = boxes.map((box) => box.size.width).toSet();
    expect(widths, hasLength(1), reason: '所有卡片应等宽，不能有卡片跨两列');
    expect(widths.single, closeTo((1000 - 32 - 16) / 2, 3));
    final lefts = boxes.map((box) => box.localToGlobal(Offset.zero).dx).toSet();
    expect(lefts, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('内容宽度不足 760 时单列，卡片不再分栏', (tester) async {
    await pumpBoard(tester, 700);

    expect(find.byType(MasonryGrid), findsNothing);
    final boxes = [
      for (final key in ['short', 'tall', 'medium'])
        tester.renderObject<RenderBox>(find.byKey(ValueKey(key))),
    ];
    final widths = boxes.map((box) => box.size.width).toSet();
    expect(widths, hasLength(1));
    expect(widths.single, closeTo(700 - 32, 3));
    final lefts = boxes.map((box) => box.localToGlobal(Offset.zero).dx).toSet();
    expect(lefts, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
