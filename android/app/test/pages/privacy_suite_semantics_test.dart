import 'package:diting_android/pages/network/privacy_suite_page.dart';
import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/app_host.dart';

void main() {
  testWidgets('隐私开关带标题语义标签', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      ProviderScope(
        child: AppHost(
          size: const Size(400, 800),
          child: const PrivacySuitePage(),
        ),
      ),
    );
    await tester.pump();

    final l10n = await AppL10n.delegate.load(const Locale('zh'));
    final labels = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .map((widget) => widget.properties.label)
        .toList();
    expect(labels, contains(l10n.privacyBlockHttpsSvcb));
    expect(labels, contains(l10n.privacyRebinding));
    expect(find.byType(CommonSwitch), findsNWidgets(2));
    handle.dispose();
  });
}
