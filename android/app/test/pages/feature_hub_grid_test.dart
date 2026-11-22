import 'package:diting_android/pages/hub/feature_hub_grid.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/app_host.dart';

void main() {
  Future<void> pumpCategory(WidgetTester tester, int count) async {
    await tester.pumpWidget(
      AppHost(
        child: Scaffold(
          body: FeatureHubCategorySection(
            category: FeatureHubCategoryData(
              title: '应用与网络',
              cards: [
                for (var i = 0; i < count; i++)
                  FeatureHubCardData(
                    title: '卡片 $i',
                    description: '说明',
                    glyph: TablerIcons.info_circle,
                    onTap: () {},
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('奇数张卡片时最后一张保持半宽', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpCategory(tester, 3);

    final cards = find.byType(AnimatedScale);
    expect(cards, findsNWidgets(3));
    final firstWidth = tester.getSize(cards.at(0)).width;
    final secondWidth = tester.getSize(cards.at(1)).width;
    final lastWidth = tester.getSize(cards.at(2)).width;
    expect(secondWidth, firstWidth);
    expect(lastWidth, firstWidth);
  });
}
