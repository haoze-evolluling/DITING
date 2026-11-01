/// Split-DNS routes: private suffixes sent to a dedicated server, with `*.internal` wildcards.
/// `ConditionalRoutesCard.vue` is the blueprint; the map the service stores is sent whole.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/widgets/desktop_feedback.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class ConditionalRoutesCard extends StatelessWidget {
  const ConditionalRoutesCard({
    super.key,
    required this.routes,
    required this.saving,
    required this.onChanged,
  });

  final Map<String, String> routes;
  final bool saving;
  final ValueChanged<Map<String, String>> onChanged;

  Future<void> _add(BuildContext context) async {
    final route = await _showRouteEditor(context);
    if (route == null || !context.mounted) return;
    onChanged({...routes, route.domain: route.server});
  }

  Future<void> _edit(BuildContext context, String domain) async {
    final route = await _showRouteEditor(
      context,
      domain: domain,
      server: routes[domain] ?? '',
    );
    if (route == null || !context.mounted) return;
    final next = {...routes};
    if (route.domain != domain) next.remove(domain);
    next[route.domain] = route.server;
    onChanged(next);
  }

  Future<void> _delete(BuildContext context, String domain) async {
    final l10n = context.l10n;
    final confirmed = await confirmDesktopAction(
      context,
      title: l10n.desktopUpstreamDeleteTitle,
      body: l10n.desktopUpstreamRouteDeleteBody(domain),
      confirmLabel: l10n.commonDelete,
    );
    if (!confirmed || !context.mounted) return;
    onChanged({...routes}..remove(domain));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DashboardCard(
      semanticLabel: l10n.desktopUpstreamRoutesTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.swap,
            title: l10n.desktopUpstreamRoutesTitle,
            leading: [
              if (routes.isNotEmpty)
                DashboardChip(label: '${routes.length}'),
            ],
            trailing: [
              DashboardIconButton(
                glyph: AppGlyphs.addCircle,
                tooltip: l10n.desktopUpstreamRoutesAdd,
                onPressed: saving ? null : () => _add(context),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopUpstreamRoutesBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          if (routes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                l10n.desktopUpstreamRoutesEmpty,
                textAlign: TextAlign.center,
                style: DashboardText.label(context),
              ),
            )
          else
            for (final entry in routes.entries)
              Padding(
                padding: EdgeInsets.only(
                  bottom: entry.key == routes.keys.last ? 0 : 8,
                ),
                child: _RouteRow(
                  domain: entry.key,
                  server: entry.value,
                  onEdit: saving ? null : () => _edit(context, entry.key),
                  onDelete: saving
                      ? null
                      : () => _delete(context, entry.key),
                ),
              ),
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.domain,
    required this.server,
    required this.onEdit,
    required this.onDelete,
  });

  final String domain;
  final String server;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    return DashboardBlock(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        spacing: 8,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  domain,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.rowTitle(context),
                ),
                Text(
                  server,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption1
                      .of(context)
                      .toTabular
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.commonEdit,
            onPressed: onEdit,
            icon: const GlyphIcon(AppGlyphs.settings, size: 18),
          ),
          IconButton(
            tooltip: l10n.commonDelete,
            onPressed: onDelete,
            icon: GlyphIcon(
              AppGlyphs.delete,
              size: 18,
              color: colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }
}

typedef _Route = ({String domain, String server});

Future<_Route?> _showRouteEditor(
  BuildContext context, {
  String domain = '',
  String server = '',
}) => showFloatingDialog<_Route>(
  context: context,
  child: _RouteEditor(domain: domain, server: server),
);

class _RouteEditor extends StatefulWidget {
  const _RouteEditor({required this.domain, required this.server});

  final String domain;
  final String server;

  @override
  State<_RouteEditor> createState() => _RouteEditorState();
}

class _RouteEditorState extends State<_RouteEditor> {
  late final _domain = TextEditingController(text: widget.domain);
  late final _server = TextEditingController(text: widget.server);
  String? _error;

  @override
  void dispose() {
    _domain.dispose();
    _server.dispose();
    super.dispose();
  }

  void _save() {
    final domain = _domain.text.trim().toLowerCase();
    final server = _server.text.trim();
    if (domain.isEmpty || server.isEmpty) {
      setState(() => _error = context.l10n.desktopUpstreamRouteInvalid);
      return;
    }
    popFloatingDialog(context, (domain: domain, server: server));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CommonDialog(
      title: l10n.desktopUpstreamRoutesAdd,
      hasFields: true,
      width: 420,
      actions: [
        TextButton(
          onPressed: () => popFloatingDialog(context),
          child: Text(l10n.commonCancel),
        ),
        TextButton(onPressed: _save, child: Text(l10n.commonSave)),
      ],
      child: SizedBox(
        width: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            TextFormField(
              controller: _domain,
              decoration: InputDecoration(
                labelText: l10n.desktopUpstreamRouteDomain,
                hintText: '*.corp.internal',
              ),
              style: AppTextStyle.callout.of(context),
            ),
            TextFormField(
              controller: _server,
              decoration: InputDecoration(
                labelText: l10n.desktopUpstreamRouteServer,
                hintText: '10.0.0.1:53',
              ),
              style: AppTextStyle.callout.of(context),
            ),
            if (_error case final error?)
              Text(
                error,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.caption1
                    .of(context)
                    .copyWith(color: context.colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}
