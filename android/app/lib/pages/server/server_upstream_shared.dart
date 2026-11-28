import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const serverUpstreamModes = <String>[
  'primary_backup',
  'single',
  'parallel_race',
  'smart_prediction',
];

/// 从属数值行的占位 leading：与父行 20px 图标等宽，保证标题左对齐。
const serverCacheNestedLeading = SizedBox(width: 20);

IconData serverModeGlyph(String mode) => switch (mode) {
  'single' => TablerIcons.cloud_upload,
  'parallel_race' => TablerIcons.gauge,
  'smart_prediction' => TablerIcons.sparkles,
  _ => TablerIcons.arrows_exchange,
};

String serverModeLabel(BuildContext context, String mode) => switch (mode) {
  'single' => context.l10n.serverModeSingle,
  'parallel_race' => context.l10n.serverModeParallel,
  'smart_prediction' => context.l10n.serverModeSmart,
  _ => context.l10n.serverModePrimaryBackup,
};

String serverModeDescription(BuildContext context, String mode) =>
    switch (mode) {
      'single' => context.l10n.serverModeSingleDesc,
      'parallel_race' => context.l10n.serverModeParallelDesc,
      'smart_prediction' => context.l10n.serverModeSmartDesc,
      _ => context.l10n.serverModePrimaryBackupDesc,
    };

Future<void> saveServerCache(
  BuildContext context,
  WidgetRef ref,
  ServerConfig config,
  ServerCacheConfig cache,
) async {
  try {
    await ref
        .read(serverControllerProvider.notifier)
        .saveConfig(config.copyWith(cache: cache));
    if (context.mounted) showAppSnack(context, context.l10n.serverCacheSaved);
  } catch (error) {
    if (context.mounted) showAppSnack(context, error.toString());
  }
}

class ServerCacheValue extends StatelessWidget {
  const ServerCacheValue({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTextRole.supportingText
          .of(context)
          .copyWith(
            color: context.colorScheme.onSurfaceVariant,
            fontFeatures: appTabularFigures,
          ),
    );
  }
}
