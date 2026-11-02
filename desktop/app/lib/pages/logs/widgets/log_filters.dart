/// The log search filters and the destructive action that empties the retained history.
///
/// The conditions match the old desktop console's search card
/// (`frontend/src/components/overview/QueryHistoryPanel.vue`): domain contains, client IP or host
/// name, one record type, one status. The controls are the app's own picker and search field, so a
/// filter reads the same here as anywhere else in the shell.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_models.dart';
import 'package:diting_desktop/data/api/desktop_log_providers.dart';
import 'package:diting_desktop/widgets/desktop_picker.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Wide enough for a domain and narrow enough that both fields and the two pickers share one row.
const double _fieldWidth = 210;

/// The status word a filter or a row uses; one source, so the picker and the empty state cannot
/// disagree about what "cached" is called.
String logStatusLabel(BuildContext context, DesktopLogStatus status) {
  final l10n = context.l10n;
  return switch (status) {
    DesktopLogStatus.all => l10n.commonAll,
    DesktopLogStatus.passed => l10n.logPassed,
    DesktopLogStatus.blocked => l10n.logBlocked,
    DesktopLogStatus.cached => l10n.logCacheHits,
    DesktopLogStatus.error => l10n.logFailed,
  };
}

/// The active conditions in words, for the empty state's description.
String logFilterLabel(BuildContext context, DesktopLogQuery query) {
  return [
    if (query.status != DesktopLogStatus.all)
      logStatusLabel(context, query.status),
    if (query.qtype.isNotEmpty) query.qtype,
    if (query.domain.isNotEmpty) query.domain,
    if (query.client.isNotEmpty) query.client,
  ].join(' · ');
}

/// Both search fields, both pickers and the clear action. The controllers live in the table that
/// owns the search debounce; this bar only renders them.
class LogFilterBar extends ConsumerWidget {
  const LogFilterBar({
    super.key,
    required this.domain,
    required this.client,
    required this.onDomainChanged,
    required this.onClientChanged,
    required this.wide,
  });

  final TextEditingController domain;
  final TextEditingController client;
  final ValueChanged<String> onDomainChanged;
  final ValueChanged<String> onClientChanged;

  /// Whether the fields and pickers can share one row.
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final query = ref.watch(desktopLogQueryProvider);
    final domainField = SearchField(
      controller: domain,
      hintText: l10n.desktopLogDomainHint,
      onChanged: onDomainChanged,
      onSubmitted: () => ref
          .read(desktopLogQueryProvider.notifier)
          .setDomain(domain.text),
    );
    final clientField = SearchField(
      controller: client,
      hintText: l10n.desktopLogClientHint,
      onChanged: onClientChanged,
      onSubmitted: () => ref
          .read(desktopLogQueryProvider.notifier)
          .setClient(client.text),
    );
    final controls = <Widget>[
      _StatusPicker(query: query),
      _TypePicker(query: query),
      if (query.isFiltered)
        TextButton(
          onPressed: () {
            domain.clear();
            client.clear();
            ref.read(desktopLogQueryProvider.notifier).reset();
          },
          child: Text(l10n.obsClearFilter),
        ),
      const _ClearHistoryButton(),
    ];
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          domainField,
          clientField,
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: controls,
          ),
        ],
      );
    }
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(width: _fieldWidth, child: domainField),
        SizedBox(width: _fieldWidth, child: clientField),
        ...controls,
      ],
    );
  }
}

class _StatusPicker extends ConsumerWidget {
  const _StatusPicker({required this.query});

  final DesktopLogQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DesktopPicker(
      glyph: AppGlyphs.filter,
      semanticLabel: context.l10n.obsStatus,
      label: logStatusLabel(context, query.status),
      active: query.status != DesktopLogStatus.all,
      items: [
        for (final status in DesktopLogStatus.values)
          CommonPopupMenuItem(
            label: logStatusLabel(context, status),
            checked: status == query.status,
            onPressed: () =>
                ref.read(desktopLogQueryProvider.notifier).setStatus(status),
          ),
      ],
    );
  }
}

class _TypePicker extends ConsumerWidget {
  const _TypePicker({required this.query});

  final DesktopLogQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final notifier = ref.read(desktopLogQueryProvider.notifier);
    return DesktopPicker(
      glyph: AppGlyphs.sort,
      semanticLabel: l10n.logsRecordType,
      label: query.qtype.isEmpty ? l10n.desktopLogAllTypes : query.qtype,
      active: query.qtype.isNotEmpty,
      items: [
        CommonPopupMenuItem(
          label: l10n.desktopLogAllTypes,
          checked: query.qtype.isEmpty,
          onPressed: () => notifier.setQType(''),
        ),
        for (final type in desktopLogQTypes)
          CommonPopupMenuItem(
            label: type,
            checked: type == query.qtype,
            onPressed: () => notifier.setQType(type),
          ),
      ],
    );
  }
}

/// Empties the service's retained history. Behind a confirm, because the service keeps no undo.
class _ClearHistoryButton extends ConsumerWidget {
  const _ClearHistoryButton();

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: l10n.desktopLogClearTitle,
        destructive: true,
        actions: [
          TextButton(
            onPressed: () => popFloatingDialog(context, false),
            child: Text(l10n.configCancel),
          ),
          TextButton(
            onPressed: () => popFloatingDialog(context, true),
            child: Text(l10n.desktopLogClear),
          ),
        ],
        child: Text(l10n.desktopLogClearBody),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final error = await ref.read(desktopLogClearProvider.notifier).clear();
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          error == null
              ? l10n.desktopLogClearDone
              : l10n.desktopLogClearFailed(error.message),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final pending = ref.watch(desktopLogClearProvider).pending;
    final color = context.colorScheme.error;
    return TextButton(
      onPressed: pending ? null : () => _clear(context, ref),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          if (pending)
            const SizedBox.square(dimension: 14, child: CommonCircleLoading())
          else
            GlyphIcon(AppGlyphs.delete, size: 16, color: color),
          Text(
            l10n.desktopLogClear,
            style: AppTextStyle.callout.of(context).copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
