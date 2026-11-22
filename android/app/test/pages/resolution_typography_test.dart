import 'package:diting_android/pages/hub/resolution_mode_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/app_host.dart';

void main() {
  testWidgets('解析模式列表保持 17/22 标题与 13/18 说明', (tester) async {
    await tester.pumpWidget(
      ProviderScope(child: const AppHost(child: ResolutionModePage())),
    );
    await tester.pumpAndSettle();

    final tile = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .firstWhere((tile) => tile.subtitle != null);

    expect(tile.titleTextStyle?.fontSize, 17);
    expect(tile.titleTextStyle?.height, closeTo(22 / 17, 0.001));
    expect(tile.subtitleTextStyle?.fontSize, 13);
    expect(tile.subtitleTextStyle?.height, closeTo(18 / 13, 0.001));
  });
}
