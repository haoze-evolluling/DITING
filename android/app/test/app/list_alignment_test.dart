import 'package:diting_android/widgets/leading_slot.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/app_host.dart';

void main() {
  Map<String, double> leftEdges(WidgetTester tester, List<String> labels) => {
    for (final label in labels)
      if (find.text(label).evaluate().isNotEmpty)
        label: tester.getTopLeft(find.text(label).first).dx,
  };

  testWidgets('LeadingSlot 让不同宽度的前置图标落在同一列', (tester) async {
    await tester.pumpWidget(
      AppHost(
        child: Scaffold(
          body: ListView(
            children: [
              generateSection(
                items: [
                  ListItem(
                    leading: const LeadingSlot(
                      child: Icon(TablerIcons.heart, size: 20),
                    ),
                    title: const Text('窄图标'),
                  ),
                  ListItem(
                    leading: LeadingSlot(
                      child: SizedBox.square(
                        dimension: 34,
                        child: const ColoredBox(color: Color(0x11000000)),
                      ),
                    ),
                    title: const Text('徽章'),
                  ),
                  ListItem(
                    leading: const LeadingSlot(
                      child: SizedBox.square(dimension: 40),
                    ),
                    title: const Text('应用图标'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final edges = leftEdges(tester, const ['窄图标', '徽章', '应用图标']);
    expect(edges, hasLength(3));
    expect(
      edges.values.toSet(),
      hasLength(1),
      reason: 'LeadingSlot 未能把不同宽度的前置图标对齐：$edges',
    );
  });
}
