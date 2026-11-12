/// Request-log CSV export (功能: 从“请求”页导出). The user picks filters and columns here; the
/// actual file is written by [RequestLogExportActions] behind [requestLogExportRunnerProvider].
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/db/http_request_repository.dart'
    show RequestSource, RequestStatus;
import 'package:diting_android/data/export/request_log_export_options.dart';
import 'package:diting_android/pages/forms/custom_issue.dart';
import 'package:diting_android/pages/forms/form_page.dart';
import 'package:diting_android/state/installed_apps_providers.dart';
import 'package:diting_android/state/observability_providers.dart'
    show AppRequestCount, requestAppCountsProvider, requestFeedQueryProvider;
import 'package:diting_android/state/request_export_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart'
    show AppWorkMode, workModeProvider;
import 'package:diting_android/widgets/app_icon_avatar.dart';
import 'package:diting_android/widgets/chip_row.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

part 'request_export_apps_sheet.dart';

class RequestLogExportPage extends ConsumerStatefulWidget {
  const RequestLogExportPage({super.key});

  @override
  ConsumerState<RequestLogExportPage> createState() =>
      _RequestLogExportPageState();
}

class _RequestLogExportPageState extends ConsumerState<RequestLogExportPage> {
  late RequestSource _source;
  late RequestStatus _status;
  RequestLogExportRange _range = RequestLogExportRange.all;
  DateTimeRange? _customRange;

  /// Empty means every app, matching [RequestLogExportOptions.packages].
  final Set<String> _packages = {};

  final Set<RequestLogColumn> _columns = {...RequestLogColumn.values};
  late final TextEditingController _limitController;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // "Export what I am looking at": seed the record filters from the request page.
    final query = ref.read(requestFeedQueryProvider);
    _source = query.source;
    _status = query.status;
    _limitController = TextEditingController(
      text: '$requestLogExportDefaultRows',
    );
  }

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
  }

  int get _maxRows => int.tryParse(_limitController.text.trim()) ?? 0;

  String? _validationError(AppL10n l10n) {
    if (_columns.isEmpty) return l10n.obsExportAtLeastOneColumn;
    if (_maxRows < 1 || _maxRows > requestLogExportMaxRows) {
      return l10n.obsExportInvalidLimit(requestLogExportMaxRows);
    }
    if (_range == RequestLogExportRange.custom &&
        (_customRange == null ||
            _customRange!.end.isBefore(_customRange!.start))) {
      return l10n.obsExportPickRange;
    }
    return null;
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _customRange,
    );
    if (picked != null && mounted) setState(() => _customRange = picked);
  }

  Future<void> _pickApps() async {
    final picked = await showRequestLogExportAppPicker(
      context,
      initial: _packages,
    );
    if (picked != null && mounted) {
      setState(
        () => _packages
          ..clear()
          ..addAll(picked),
      );
    }
  }

  void _reset() {
    setState(() {
      _source = RequestSource.all;
      _status = RequestStatus.all;
      _range = RequestLogExportRange.all;
      _customRange = null;
      _packages.clear();
      _columns
        ..clear()
        ..addAll(RequestLogColumn.values);
      _limitController.text = '$requestLogExportDefaultRows';
    });
  }

  Future<void> _export(AppL10n l10n) async {
    final error = _validationError(l10n);
    if (error != null) {
      _toast(error);
      return;
    }
    final range = _customRange;
    final options = RequestLogExportOptions(
      source: _source,
      status: _status,
      packages: {..._packages},
      range: _range,
      customStart: range?.start,
      // The picked dates are calendar days: include the whole end day.
      customEnd: range == null
          ? null
          : DateTime(
              range.end.year,
              range.end.month,
              range.end.day,
              23,
              59,
              59,
              999,
            ),
      maxRows: _maxRows,
      columns: {..._columns},
    );
    setState(() => _busy = true);
    try {
      final outcome = await ref.read(requestLogExportRunnerProvider)(options);
      if (!mounted) return;
      if (outcome.cancelled) {
        _toast(l10n.obsExportCancelled);
        return;
      }
      if (outcome.error != null) {
        _toast(outcome.error!);
        return;
      }
      final result = outcome.result;
      if (result == null) {
        _toast(l10n.obsExportEmpty);
        return;
      }
      _toast(
        '${l10n.obsExportDone(result.count)}'
        '${result.truncated ? ' · ${l10n.obsExportTruncated(_maxRows)}' : ''}',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final normalMode = ref.watch(workModeProvider) == AppWorkMode.normal;
    final error = _validationError(l10n);
    // A custom range starts out empty by design; the row's own hint explains what
    // to do, so don't greet the user with a red banner the moment they tap 自定义.
    final showError =
        error != null &&
        !(_range == RequestLogExportRange.custom && _customRange == null);

    return CommonScaffold(
      title: l10n.obsExportTitle,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.reset,
          tooltip: l10n.commonReset,
          onPressed: _busy ? null : _reset,
        ),
      ],
      body: PageBody(
        children: [
          PageIntroCard(text: l10n.obsExportIntro),
          _ExportCard(
            title: l10n.obsExportRangeSection,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: ChipRow(
                  children: [
                    for (final option in RequestLogExportRange.values)
                      FilterPill(
                        label: _rangeLabel(l10n, option),
                        selected: option == _range,
                        onPressed: option == _range
                            ? null
                            : () => setState(() => _range = option),
                      ),
                  ],
                ),
              ),
              if (_range == RequestLogExportRange.custom) ...[
                _divider(context),
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.clock, size: 20),
                  title: Text(l10n.obsExportCustomRange),
                  subtitle: Text(
                    _customRange == null
                        ? l10n.obsExportPickRange
                        : _rangeText(_customRange!),
                  ),
                  trailing: GlyphIcon(
                    AppGlyphs.chevronForward,
                    size: 18,
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                  onTap: _pickCustomRange,
                ),
              ],
            ],
          ),
          _ExportCard(
            title: l10n.obsExportScopeSection,
            children: [
              _ExportField(
                label: l10n.obsSource,
                hint: normalMode ? null : l10n.obsExportDnsOnlyNote,
                child: ChipRow(
                  children: [
                    for (final option in RequestSource.values)
                      FilterPill(
                        label: option.label,
                        selected: option == _source,
                        onPressed: option == _source
                            ? null
                            : () => setState(() => _source = option),
                      ),
                  ],
                ),
              ),
              _divider(context),
              _ExportField(
                label: l10n.obsStatus,
                child: ChipRow(
                  children: [
                    for (final option in RequestStatus.values)
                      FilterPill(
                        label: option.label,
                        selected: option == _status,
                        onPressed: option == _status
                            ? null
                            : () => setState(() => _status = option),
                      ),
                  ],
                ),
              ),
              _divider(context),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.appsList, size: 20),
                title: Text(
                  _packages.isEmpty
                      ? l10n.obsExportAllApps
                      : l10n.obsExportSelectedApps(_packages.length),
                ),
                trailing: GlyphIcon(
                  AppGlyphs.chevronForward,
                  size: 18,
                  color: context.colorScheme.onSurfaceVariant,
                ),
                onTap: _pickApps,
              ),
              _divider(context),
              SurfaceScope(
                level: SurfaceLevel.page,
                child: FormRowTextField(
                  title: l10n.obsExportLimit,
                  controller: _limitController,
                  keyboardType: TextInputType.number,
                  machineText: true,
                  hintText: l10n.obsExportLimitHint(requestLogExportMaxRows),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          _ExportCard(
            title: l10n.obsExportColumnsSection,
            footer: l10n.obsExportSelectedColumns(_columns.length),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final column in RequestLogColumn.values)
                      FilterPill(
                        label: column.header(l10n),
                        selected: _columns.contains(column),
                        onPressed: () => setState(() {
                          if (!_columns.remove(column)) _columns.add(column);
                        }),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (showError)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: ErrorBanner(message: error!),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TonalButton(
              label: _busy ? l10n.obsExportBusy : l10n.obsExportAction,
              glyph: _busy ? null : AppGlyphs.export,
              onPressed: _busy || error != null ? null : () => _export(l10n),
            ),
          ),
          ListFooter(text: l10n.obsExportFooter),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) => Divider(
    height: 1,
    indent: 16,
    endIndent: 16,
    color: context.colorScheme.outlineVariant,
  );

  String _rangeLabel(AppL10n l10n, RequestLogExportRange range) =>
      switch (range) {
        RequestLogExportRange.all => l10n.obsExportRangeAll,
        RequestLogExportRange.hour => l10n.obsExportRangeHour,
        RequestLogExportRange.day => l10n.obsExportRangeDay,
        RequestLogExportRange.week => l10n.obsExportRangeWeek,
        RequestLogExportRange.custom => l10n.obsExportRangeCustom,
      };

  String _rangeText(DateTimeRange range) {
    String date(DateTime time) {
      String two(int value) => value.toString().padLeft(2, '0');
      return '${time.year}-${two(time.month)}-${two(time.day)}';
    }

    return '${date(range.start)} ~ ${date(range.end)}';
  }
}

/// One titled card: header, a single card holding grouped rows and chips, then an optional note.
/// The card carries no padding so rows (a tappable [ListItem]) can reach its rounded edge.
class _ExportCard extends StatelessWidget {
  const _ExportCard({required this.title, required this.children, this.footer});

  final String title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final footer = this.footer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListHeader(title: title),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: CommonCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
        if (footer != null) ListFooter(text: footer),
      ],
    );
  }
}

/// A labelled field inside an [_ExportCard]: caption above the control, optional caption below.
class _ExportField extends StatelessWidget {
  const _ExportField({required this.label, required this.child, this.hint});

  final String label;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final hint = this.hint;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Text(label, style: context.listCaptionStyle),
          child,
          if (hint != null) Text(hint, style: context.listCaptionStyle),
        ],
      ),
    );
  }
}
