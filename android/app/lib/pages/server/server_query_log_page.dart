import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/pages/server/server_common.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ServerQueryLogPage extends ConsumerWidget {
  const ServerQueryLogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(serverControllerProvider).value;
    if (snapshot == null) {
      return CommonScaffold(
        title: context.l10n.serverQueryLogTitle,
        body: const Center(child: CommonCircleLoading()),
      );
    }
    final config = snapshot.config;
    final queryLog = config.queryLog;
    Future<void> save(ServerQueryLogConfig next) async {
      try {
        await ref
            .read(serverControllerProvider.notifier)
            .saveConfig(config.copyWith(queryLog: next));
        if (context.mounted) {
          showAppSnack(context, context.l10n.serverQueryLogSaved);
        }
      } catch (error) {
        if (context.mounted) showAppSnack(context, error.toString());
      }
    }

    return CommonScaffold(
      title: context.l10n.serverQueryLogTitle,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.serverQueryLogContent,
            items: [
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.logs, size: 20),
                title: Text(context.l10n.serverQueryLogEnabled),
                subtitle: Text(context.l10n.serverQueryLogEnabledBody),
                value: queryLog.enabled,
                onChanged: (value) => save(queryLog.copyWith(enabled: value)),
              ),
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.export, size: 20),
                title: Text(context.l10n.serverQueryLogFile),
                subtitle: Text(context.l10n.serverQueryLogFileBody),
                value: queryLog.fileEnabled,
                onChanged: (value) =>
                    save(queryLog.copyWith(fileEnabled: value)),
              ),
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.devices, size: 20),
                title: Text(context.l10n.serverQueryLogClients),
                subtitle: Text(context.l10n.serverQueryLogClientsBody),
                value: queryLog.logClients,
                onChanged: (value) =>
                    save(queryLog.copyWith(logClients: value)),
              ),
            ],
          ),
          const ListSectionGap(),
          generateSection(
            items: [
              ServerOptionRow<int>(
                glyph: AppGlyphs.clock,
                title: context.l10n.serverQueryLogRetention,
                value: queryLog.retentionDays,
                options: [
                  for (final days in const [1, 7, 30, 90])
                    ServerOption(
                      value: days,
                      label: context.l10n.serverLogDays(days),
                    ),
                ],
                onChanged: (days) =>
                    save(queryLog.copyWith(retentionDays: days)),
              ),
            ],
            footer: context.l10n.serverQueryLogRetentionNote,
          ),
          generateSection(
            title: context.l10n.serverQueryLogMemory,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.memory, size: 20),
                title: Text(context.l10n.serverQueryLogMemoryEntries),
                trailing: _NumberValue(label: '${queryLog.maxEntries}'),
                onTap: () async {
                  final value = await editServerNumber(
                    context,
                    title: context.l10n.serverQueryLogMemoryEntries,
                    initial: queryLog.maxEntries,
                    max: 200000,
                  );
                  if (value != null) {
                    await save(queryLog.copyWith(maxEntries: value));
                  }
                },
              ),
            ],
            footer: context.l10n.serverQueryLogMemoryNote,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _NumberValue extends StatelessWidget {
  const _NumberValue({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTextStyle.footnote
          .of(context)
          .copyWith(
            color: context.colorScheme.onSurfaceVariant,
            fontFeatures: appTabularFigures,
          ),
    );
  }
}
