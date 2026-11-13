// ignore_for_file: sort_child_properties_last
import 'package:diting_shared/app/l10n/l10n.dart';

import 'package:diting_android/data/db/bootstrap_log_repository.dart';
import 'package:diting_shared/data/db/legacy_database.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite/sqflite.dart';

/// Bootstrap resolution settings (upstream `BootstrapSettingsScreen`). Reads and writes
/// `bootstrap_enabled`, `bootstrap_preset_ids` and `bootstrap_custom_json` in
/// `dns_vpn_prefs`; counts come from `bootstrap_log`.
class BootstrapSettingsPage extends ConsumerWidget {
  const BootstrapSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(legacySettingsProvider);
    final enabled = settings.bootstrapEnabled;
    final selected = settings.bootstrapPresetIds.toSet();
    final custom = _readCustom(settings.bootstrapCustomJson);
    final stats = ref.watch(bootstrapStatsProvider);
    final statById = {
      for (final row in stats.value ?? const <BootstrapIpStat>[])
        if (row.id.isNotEmpty) row.id: row,
    };
    return CommonScaffold(
      title: context.l10n.bootstrapTitle,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.add,
          tooltip: context.l10n.bootstrapAdd,
          onPressed: () => _add(context, ref, custom),
        ),
      ],
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.bootstrapGlobal,
            items: [
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.language),
                title: Text(context.l10n.bootstrapEnable),
                subtitle: Text(context.l10n.bootstrapEnableBody),
                value: enabled,
                onChanged: (value) {
                  settings.setBootstrapEnabled(value);
                  ref.read(legacySettingsRevisionProvider.notifier).bump();
                },
              ),
            ],
            footer: context.l10n.bootstrapEnableNote,
          ),
          generateSection(
            title: context.l10n.bootstrapBuiltin,
            items: [
              for (final entry in defaultBootstrapEntries(context.l10n))
                _BootstrapRow(
                  entry: entry,
                  selected: selected.contains(entry.id),
                  enabled: enabled,
                  stat: statById[entry.id],
                  onChanged: (value) {
                    final next = {...selected};
                    value ? next.add(entry.id) : next.remove(entry.id);
                    settings.setBootstrapPresetIds(next);
                    ref.read(legacySettingsRevisionProvider.notifier).bump();
                  },
                ),
            ],
          ),
          generateSection(
            title: context.l10n.bootstrapCustom,
            items: [
              if (custom.isEmpty)
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.info),
                  title: Text(context.l10n.bootstrapNoCustom),
                ),
              for (final entry in custom)
                _BootstrapRow(
                  entry: entry,
                  selected: entry.enabled,
                  enabled: enabled,
                  stat: statById[entry.id],
                  onChanged: (value) => _writeCustom(ref, [
                    for (final item in custom)
                      item.id == entry.id
                          ? BootstrapEntry(
                              item.id,
                              item.name,
                              item.ip,
                              enabled: value,
                            )
                          : item,
                  ]),
                  onDelete: () => _writeCustom(ref, [
                    for (final item in custom)
                      if (item.id != entry.id) item,
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    List<BootstrapEntry> custom,
  ) async {
    final draft = await showFloatingDialog<({String name, String ip})>(
      context: context,
      child: const _BootstrapEditor(),
    );
    if (draft == null) {
      return;
    }
    _writeCustom(ref, [
      ...custom,
      BootstrapEntry(
        'custom_${DateTime.now().microsecondsSinceEpoch}',
        draft.name.isEmpty ? draft.ip : draft.name,
        draft.ip,
      ),
    ]);
  }

  void _writeCustom(WidgetRef ref, List<BootstrapEntry> entries) {
    ref
        .read(legacySettingsProvider)
        .setBootstrapCustomJson(encodeCustomBootstrapEntries(entries));
    ref.read(legacySettingsRevisionProvider.notifier).bump();
  }

  /// `bootstrap_custom_json` is a JSON array of `{id,name,ip,enabled}`; the row shape and the
  /// fallbacks live in the kernel.
  static List<BootstrapEntry> _readCustom(String? raw) =>
      parseCustomBootstrapEntries(raw);
}

/// 24-hour aggregate of `bootstrap_log` in the active mode's log database; empty on a fresh
/// install or when bootstrap probing never ran.
final bootstrapStatsProvider = FutureProvider<List<BootstrapIpStat>>((
  ref,
) async {
  final db = await LegacyDatabase.open(
    ref.watch(activeLogDatabaseFileProvider),
  );
  if (db == null) return const [];
  return _readStats(db);
});

Future<List<BootstrapIpStat>> _readStats(Database db) async {
  try {
    return await BootstrapLogRepository(db).recentStats();
  } on DatabaseException {
    // Older installs may predate the table; an empty list is the honest answer.
    return const [];
  }
}

class _BootstrapRow extends StatelessWidget {
  const _BootstrapRow({
    required this.entry,
    required this.selected,
    required this.enabled,
    required this.onChanged,
    this.stat,
    this.onDelete,
  });

  final BootstrapEntry entry;
  final bool selected;
  final bool enabled;
  final BootstrapIpStat? stat;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onDelete;

  String get _subtitle {
    final row = stat;
    if (row == null || row.attempts == 0) {
      return currentL10n.bootstrapNoSample(entry.ip);
    }
    final success = (row.successes * 100 / row.attempts).round();
    final latency = row.averageElapsedMs == null
        ? ''
        : currentL10n.bootstrapAverage('${row.averageElapsedMs!.round()}');
    return currentL10n.bootstrapStats(
      entry.ip,
      latency,
      '${row.attempts}',
      '$success',
      row.failures > 0 ? currentL10n.bootstrapFailures('${row.failures}') : '',
    );
  }

  @override
  Widget build(BuildContext context) {
    final failing = (stat?.failures ?? 0) > 0;
    return ListItem(
      leading: GlyphIcon(
        failing ? AppGlyphs.warning : AppGlyphs.status,
        size: 20,
      ),
      title: Text(entry.name),
      subtitle: Text(_subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CommonCheckBox(
            value: selected,
            onChanged: enabled ? (value) => onChanged(value ?? true) : null,
          ),
          if (onDelete != null)
            IconButton(
              tooltip: context.l10n.appRulesDelete,
              onPressed: enabled ? onDelete : null,
              icon: const GlyphIcon(AppGlyphs.delete, size: 20),
            ),
        ],
      ),
      onTap: enabled ? () => onChanged(!selected) : null,
    );
  }
}

class _BootstrapEditor extends StatefulWidget {
  const _BootstrapEditor();

  @override
  State<_BootstrapEditor> createState() => _BootstrapEditorState();
}

class _BootstrapEditorState extends State<_BootstrapEditor> {
  final _name = TextEditingController();
  final _ip = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _ip.dispose();
    super.dispose();
  }

  void _save() {
    final ip = _ip.text.trim();
    final valid = RegExp(
      r'^((25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(25[0-5]|2[0-4]\d|1?\d?\d)$|^[0-9a-fA-F:]+$',
    ).hasMatch(ip);
    if (!valid) {
      setState(() => _error = currentL10n.bootstrapInvalidIp);
      return;
    }
    Navigator.of(context).pop((name: _name.text.trim(), ip: ip));
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: context.l10n.bootstrapAdd,
      hasFields: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: context.l10n.bootstrapNameOptional,
            ),
          ),
          TextField(
            controller: _ip,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: context.l10n.bootstrapIpAddress,
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: context.colorScheme.error),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.appRulesCancel),
        ),
        TextButton(
          onPressed: _save,
          child: Text(context.l10n.appSelectionSave),
        ),
      ],
    );
  }
}
