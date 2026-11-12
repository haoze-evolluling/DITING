part of 'request_export_page.dart';

/// Opens the app multi-select picker; returns the chosen packages, or null when dismissed.
Future<Set<String>?> showRequestLogExportAppPicker(
  BuildContext context, {
  required Set<String> initial,
}) {
  return showSheet<Set<String>>(
    context: context,
    builder: (_) => _RequestLogExportAppPicker(initial: initial),
  );
}

class _RequestLogExportAppPicker extends ConsumerStatefulWidget {
  const _RequestLogExportAppPicker({required this.initial});

  final Set<String> initial;

  @override
  ConsumerState<_RequestLogExportAppPicker> createState() =>
      _RequestLogExportAppPickerState();
}

class _RequestLogExportAppPickerState
    extends ConsumerState<_RequestLogExportAppPicker> {
  late final Set<String> _selected = {...widget.initial};
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(String packageName) {
    setState(() {
      if (!_selected.remove(packageName)) _selected.add(packageName);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final asyncApps = ref.watch(requestAppCountsProvider);
    final installed = ref.watch(installedAppListProvider);
    final labels = <String, String>{
      for (final app in installed ?? const []) app.packageName: app.label,
    };
    final apps = asyncApps.value ?? const <AppRequestCount>[];
    final needle = _query.trim().toLowerCase();
    final visible = needle.isEmpty
        ? apps
        : [
            for (final app in apps)
              if (app.packageName.toLowerCase().contains(needle) ||
                  (labels[app.packageName] ?? app.packageName)
                      .toLowerCase()
                      .contains(needle))
                app,
          ];

    return CommonScaffold(
      title: l10n.obsExportAppPickerTitle,
      body: ListView(
        // The sheet title floats over the body, so this top padding is required.
        padding: EdgeInsets.only(top: context.contentTopPadding, bottom: 24),
        children: [
          if (asyncApps.isLoading && !asyncApps.hasValue)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CommonCircleLoading()),
            )
          else if (asyncApps.hasError)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('${asyncApps.error}'),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SearchField(
                controller: _search,
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            ListHeader(
              title: _selected.isEmpty
                  ? l10n.obsExportAllApps
                  : l10n.obsExportSelectedApps(_selected.length),
            ),
            ListItem(
              leading: const GlyphIcon(AppGlyphs.clearAll, size: 20),
              title: Text(l10n.obsExportAllApps),
              trailing: _selected.isEmpty ? const SelectionCheck() : null,
              onTap: () => setState(_selected.clear),
            ),
            for (final app in visible)
              ListItem(
                leading: AppIconAvatar(packageName: app.packageName),
                title: Text(
                  labels[app.packageName] ?? app.packageName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${app.packageName} · ${l10n.obsAppRequestCount(app.count)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: CommonCheckBox(
                  value: _selected.contains(app.packageName),
                  isCircle: true,
                  onChanged: (_) => _toggle(app.packageName),
                ),
                onTap: () => _toggle(app.packageName),
              ),
            if (visible.isEmpty) ListFooter(text: l10n.obsAppsEmpty),
            ListItem(
              leading: const GlyphIcon(AppGlyphs.check, size: 20),
              title: Text(l10n.obsExportAppPickerDone),
              onTap: () => Navigator.of(context).pop(_selected),
            ),
          ],
        ],
      ),
    );
  }
}
