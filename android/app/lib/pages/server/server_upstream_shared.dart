import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

const serverUpstreamModes = <String>[
  'primary_backup',
  'single',
  'parallel_race',
  'smart_prediction',
];

Glyph serverModeGlyph(String mode) => switch (mode) {
  'single' => AppGlyphs.upstream,
  'parallel_race' => AppGlyphs.speed,
  'smart_prediction' => AppGlyphs.sparkle,
  _ => AppGlyphs.swap,
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
