/// The client ACL: the allow whitelist and the explicit blocklist, each edited as one entry per line.
///
/// The old desktop console's `ClientsPanel.vue` access card is the blueprint. Both lists are saved
/// together; an empty whitelist means "no restriction", and whether an address or CIDR is valid is
/// the service's call.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_traffic_models.dart';
import 'package:diting_desktop/data/api/desktop_traffic_providers.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ClientAccessCard extends ConsumerStatefulWidget {
  const ClientAccessCard({
    super.key,
    required this.access,
    required this.saving,
  });

  final DesktopAccessControl access;
  final bool saving;

  @override
  ConsumerState<ClientAccessCard> createState() => _ClientAccessCardState();
}

class _ClientAccessCardState extends ConsumerState<ClientAccessCard> {
  final _allowed = TextEditingController();
  final _blocked = TextEditingController();
  DesktopAccessControl? _adopted;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _adopt(widget.access);
  }

  @override
  void didUpdateWidget(ClientAccessCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _adopt(widget.access);
  }

  @override
  void dispose() {
    _allowed.dispose();
    _blocked.dispose();
    super.dispose();
  }

  void _adopt(DesktopAccessControl access) {
    if (identical(_adopted, access)) return;
    _adopted = access;
    if (_dirty) return;
    _allowed.text = access.allowed.join('\n');
    _blocked.text = access.blocked.join('\n');
  }

  List<String> _lines(TextEditingController controller) => [
    for (final line in controller.text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  Future<void> _save() async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopTrafficProvider.notifier)
        .saveAccess(
          DesktopAccessControl(
            allowed: _lines(_allowed),
            blocked: _lines(_blocked),
          ),
        );
    if (!mounted) return;
    if (error == null) setState(() => _dirty = false);
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopTrafficAccessSaved
          : l10n.desktopTrafficSaveFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final saving = widget.saving;
    return DashboardCard(
      semanticLabel: l10n.desktopTrafficAccessTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.rules,
            title: l10n.desktopTrafficAccessTitle,
            leading: [
              DashboardChip(
                label: widget.access.allowed.isEmpty
                    ? l10n.desktopTrafficAccessOpen
                    : l10n.desktopTrafficAccessAllowOnly,
                tone: widget.access.allowed.isEmpty
                    ? DashboardChipTone.idle
                    : DashboardChipTone.ok,
              ),
            ],
            trailing: [
              if (saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopTrafficAccessBody,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _allowed,
            minLines: 3,
            maxLines: 6,
            style: AppTextStyle.callout.of(context).toTabular,
            decoration: InputDecoration(
              labelText: l10n.desktopTrafficAccessAllowed,
              hintText: l10n.desktopTrafficAccessAllowedHint,
            ),
            onChanged: (_) => setState(() => _dirty = true),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.desktopTrafficAccessAllowedBody,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _blocked,
            minLines: 3,
            maxLines: 6,
            style: AppTextStyle.callout.of(context).toTabular,
            decoration: InputDecoration(
              labelText: l10n.desktopTrafficAccessBlocked,
              hintText: l10n.desktopTrafficAccessBlockedHint,
            ),
            onChanged: (_) => setState(() => _dirty = true),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.desktopTrafficAccessBlockedBody,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => setState(() {
                        _dirty = false;
                        _allowed.text = widget.access.allowed.join('\n');
                        _blocked.text = widget.access.blocked.join('\n');
                      }),
                child: Text(l10n.desktopTrafficAccessReset),
              ),
              FilledButton.tonal(
                onPressed: saving ? null : () => unawaited(_save()),
                child: Text(l10n.desktopTrafficAccessSave),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
