library;

import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class UnknownRoutePage extends StatelessWidget {
  const UnknownRoutePage({super.key, required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return CommonScaffold(
      title: context.l10n.unknownRouteTitle,
      body: AppBarClearance(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 12,
              children: [
                Icon(
                  TablerIcons.search,
                  size: 40,
                  color: colorScheme.onSurfaceVariant,
                ),
                Text(
                  context.l10n.unknownRouteBody,
                  textAlign: TextAlign.center,
                  style: AppTextRole.sectionTitle.of(context),
                ),
                SelectableText(
                  location,
                  textAlign: TextAlign.center,
                  style: AppTextRole.supportingText
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                TonalButton(
                  label: context.l10n.unknownRouteBack,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
