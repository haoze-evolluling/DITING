import 'package:diting_desktop/widgets/desktop_card_board.dart';
import 'package:diting_desktop/widgets/masonry_grid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pumpBoard(
    WidgetTester tester,
    double width, {
    bool singleColumn = false,
    int cards = 3,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DesktopCardBoard(
              singleColumn: singleColumn,
              cards: [
                for (final (key, height) in const [
                  ('short', 40.0),
                  ('tall', 160.0),
                  ('medium', 90.0),
                ].take(cards))
                  SizedBox(key: ValueKey(key), height: height),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const keyed = ['short', 'tall', 'medium'];

  testWidgets('内容宽度达到两列门槛后两列瀑布流，每张卡片只占一列', (tester) async {
    await pumpBoard(tester, desktopTwoColumnWidth);

    expect(find.byType(MasonryGrid), findsOneWidget);
    final boxes = [
      for (final key in keyed)
        tester.renderObject<RenderBox>(find.byKey(ValueKey(key))),
    ];
    final widths = boxes.map((box) => box.size.width).toSet();
    expect(widths, hasLength(1), reason: '所有卡片应等宽，不能有卡片跨两列');
    expect(
      widths.single,
      closeTo(
        (desktopTwoColumnWidth - desktopPageGutter * 2 - dashboardGap) / 2,
        3,
      ),
    );
    final lefts = boxes.map((box) => box.localToGlobal(Offset.zero).dx).toSet();
    expect(lefts, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('内容宽度不足两列门槛时单列，卡片不再分栏', (tester) async {
    await pumpBoard(tester, desktopTwoColumnWidth - 40);

    expect(find.byType(MasonryGrid), findsNothing);
    final boxes = [
      for (final key in keyed)
        tester.renderObject<RenderBox>(find.byKey(ValueKey(key))),
    ];
    final widths = boxes.map((box) => box.size.width).toSet();
    expect(widths, hasLength(1));
    expect(widths.single, closeTo(desktopTwoColumnWidth - 40 - 48, 3));
    final lefts = boxes.map((box) => box.localToGlobal(Offset.zero).dx).toSet();
    expect(lefts, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('两张卡片在宽屏上也是单列，且限宽居中', (tester) async {
    await pumpBoard(tester, 1400, cards: 2);

    expect(find.byType(MasonryGrid), findsNothing, reason: '两张卡片不排瀑布流');
    final boxes = [
      for (final key in keyed.take(2))
        tester.renderObject<RenderBox>(find.byKey(ValueKey(key))),
    ];
    final lefts = boxes.map((box) => box.localToGlobal(Offset.zero).dx).toSet();
    expect(lefts, hasLength(1), reason: '卡片不得并排');
    expect(boxes.first.size.width, closeTo(desktopSingleColumnMaxWidth, 3));
    final left = lefts.single;
    expect(left, closeTo((1400 - desktopSingleColumnMaxWidth) / 2, 3));
    expect(
      left,
      closeTo(1400 - left - boxes.first.size.width, 3),
      reason: '左右边距应相等',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('单列比限宽还窄时用满内容区，不留多余边距', (tester) async {
    await pumpBoard(tester, desktopTwoColumnWidth - 40, cards: 2);

    final boxes = [
      for (final key in keyed.take(2))
        tester.renderObject<RenderBox>(find.byKey(ValueKey(key))),
    ];
    expect(boxes.first.size.width, closeTo(desktopTwoColumnWidth - 40 - 48, 3));
    expect(boxes.first.localToGlobal(Offset.zero).dx, closeTo(desktopPageGutter, 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('singleColumn 在宽屏上也只排一列', (tester) async {
    await pumpBoard(tester, 1400, singleColumn: true);

    expect(find.byType(MasonryGrid), findsNothing);
    final boxes = [
      for (final key in keyed)
        tester.renderObject<RenderBox>(find.byKey(ValueKey(key))),
    ];
    final lefts = boxes.map((box) => box.localToGlobal(Offset.zero).dx).toSet();
    expect(lefts, hasLength(1), reason: '卡片不得并排');
    expect(lefts.single, closeTo(desktopPageGutter, 3));
    expect(boxes.first.size.width, closeTo(1400 - desktopPageGutter * 2, 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('只有一张卡片时不会拉满整行，并保持左右边距相等', (tester) async {
    await pumpBoard(tester, 1400, cards: 1);

    final box = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('short')),
    );
    expect(box.size.width, closeTo(desktopSingleColumnMaxWidth, 3));
    final left = box.localToGlobal(Offset.zero).dx;
    expect(left, closeTo((1400 - desktopSingleColumnMaxWidth) / 2, 3));
    expect(left, closeTo(1400 - left - box.size.width, 3));
    expect(tester.takeException(), isNull);
  });
}

/// The board's inner gap, restated here so the test fails if the constant drifts.
const dashboardGap = 16.0;
