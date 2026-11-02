/// Reverse-proxy trust for the DoH listener: the switch, the trusted sources and the forwarded header
/// the service should believe.
///
/// The old desktop console's `ReverseProxyCard.vue` is the blueprint. The switch saves on the spot and
/// the two fields are a draft that saves with its button; an unrestricted source list is warned about
/// because anyone on that network could then claim any client address.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_encrypted_models.dart';
import 'package:diting_desktop/data/api/desktop_encrypted_providers.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class EncryptedProxyCard extends ConsumerStatefulWidget {
  const EncryptedProxyCard({
    super.key,
    required this.status,
    required this.saving,
  });

  final DesktopEncryptedStatus status;
  final bool saving;

  @override
  ConsumerState<EncryptedProxyCard> createState() =>
      _EncryptedProxyCardState();
}

class _EncryptedProxyCardState extends ConsumerState<EncryptedProxyCard> {
  final _sources = TextEditingController();
  final _header = TextEditingController();
  DesktopEncryptedStatus? _adopted;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _adopt(widget.status);
  }

  @override
  void didUpdateWidget(EncryptedProxyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _adopt(widget.status);
  }

  @override
  void dispose() {
    _sources.dispose();
    _header.dispose();
    super.dispose();
  }

  void _adopt(DesktopEncryptedStatus status) {
    if (identical(_adopted, status)) return;
    _adopted = status;
    if (_dirty) return;
    _sources.text = status.config.proxyTrustedSources.join('\n');
    _header.text = status.config.proxyClientIpHeader;
  }

  List<String> get _parsedSources => [
    for (final line in _sources.text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  Future<void> _configure(
    Map<String, Object?> patch, {
    required String success,
    bool fromForm = false,
  }) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopEncryptedProvider.notifier)
        .configure(patch);
    if (!mounted) return;
    if (error == null && fromForm) setState(() => _dirty = false);
    showDesktopMessage(
      context,
      error == null ? success : l10n.desktopEncryptedSaveFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = widget.status;
    final config = status.config;
    final saving = widget.saving;
    return DashboardCard(
      semanticLabel: l10n.desktopEncryptedProxyTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.swap,
            title: l10n.desktopEncryptedProxyTitle,
            leading: [
              DashboardChip(
                label: config.proxyEnabled
                    ? l10n.commonEnabled
                    : l10n.commonDisabled,
                tone: config.proxyEnabled
                    ? DashboardChipTone.ok
                    : DashboardChipTone.idle,
                dot: config.proxyEnabled,
              ),
            ],
            trailing: [
              if (saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              else
                DashboardSwitch(
                  value: config.proxyEnabled,
                  semanticLabel: l10n.desktopEncryptedProxyTitle,
                  onChanged: (value) => unawaited(
                    _configure(
                      {
                        'reverseProxy': {'enabled': value},
                      },
                      success: value
                          ? l10n.desktopEncryptedProxyOn
                          : l10n.desktopEncryptedProxyOff,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopEncryptedProxyBody,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          if (status.unrestrictedTrust) ...[
            const SizedBox(height: 8),
            Text(
              l10n.desktopEncryptedProxyUnrestricted,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.label(
                context,
                color: context.colorScheme.warning,
              ),
            ),
          ],
          if (config.proxyEnabled) ...[
            const SizedBox(height: 10),
            Text(
              l10n.desktopEncryptedProxySources,
              style: DashboardText.rowTitle(context),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _sources,
              minLines: 3,
              maxLines: 6,
              style: AppTextStyle.callout.of(context).toMonospace,
              decoration: const InputDecoration(
                hintText: '192.168.1.0/24\n10.0.0.1',
              ),
              onChanged: (_) => setState(() => _dirty = true),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _header,
              decoration: InputDecoration(
                labelText: l10n.desktopEncryptedProxyHeader,
                hintText: 'CF-Connecting-IP',
              ),
              style: AppTextStyle.callout.of(context).toMonospace,
              onChanged: (_) => setState(() => _dirty = true),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.tonal(
                onPressed: saving
                    ? null
                    : () => unawaited(
                        _configure(
                          {
                            'reverseProxy': {
                              'enabled': true,
                              'trustedSources': _parsedSources,
                              'clientIpHeader': _header.text.trim(),
                            },
                          },
                          success: l10n.desktopEncryptedProxySaved,
                          fromForm: true,
                        ),
                      ),
                child: Text(l10n.desktopEncryptedProxySave),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
