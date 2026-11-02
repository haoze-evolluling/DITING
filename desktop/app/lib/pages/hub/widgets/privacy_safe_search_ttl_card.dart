/// The rewrite TTL of the forced safe-search answers.
///
/// The old desktop console's `SafeSearchCard.vue` keeps this number in the same card as the provider
/// list; here it is its own card, because the list already fills one and a half. The number is a
/// draft that saves with its button, and the service's clamped answer is adopted afterwards.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_privacy_models.dart';
import 'package:diting_desktop/data/api/desktop_reputation_providers.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class PrivacySafeSearchTtlCard extends ConsumerStatefulWidget {
  const PrivacySafeSearchTtlCard({super.key});

  @override
  ConsumerState<PrivacySafeSearchTtlCard> createState() =>
      _PrivacySafeSearchTtlCardState();
}

class _PrivacySafeSearchTtlCardState
    extends ConsumerState<PrivacySafeSearchTtlCard> {
  final _ttl = TextEditingController();
  DesktopSafeSearchConfig? _adopted;
  bool _dirty = false;
  bool _invalid = false;

  @override
  void dispose() {
    _ttl.dispose();
    super.dispose();
  }

  void _adopt(DesktopSafeSearchConfig config) {
    if (identical(_adopted, config)) return;
    _adopted = config;
    if (_dirty) return;
    _ttl.text = '${config.effectiveTtl}';
  }

  Future<void> _save(int ttl) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopSafeSearchProvider.notifier)
        .save({'ttl': ttl});
    if (!mounted) return;
    if (error == null) setState(() => _dirty = false);
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopSafeSearchTtlSaved
          : l10n.desktopPrivacySaveFailed('$error'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(desktopSafeSearchProvider);
    final config = state.config;
    if (config != null) _adopt(config);
    final saving = state.saving;
    return DashboardCard(
      semanticLabel: l10n.desktopSafeSearchTtlCardTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.refresh,
            title: l10n.desktopSafeSearchTtlCardTitle,
            leading: [
              if (config != null)
                DashboardChip(label: l10n.desktopSafeSearchTtlChip(config.effectiveTtl)),
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
            l10n.desktopSafeSearchTtlCardBody,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 190,
                child: TextFormField(
                  controller: _ttl,
                  enabled: config != null && !saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: l10n.desktopSafeSearchTtl,
                  ),
                  style: AppTextStyle.callout.of(context),
                  onChanged: (_) {
                    if (!_dirty) setState(() => _dirty = true);
                    if (_invalid) setState(() => _invalid = false);
                  },
                ),
              ),
              FilledButton.tonal(
                onPressed: config == null || saving
                    ? null
                    : () {
                        final ttl = int.tryParse(_ttl.text);
                        if (ttl == null || ttl <= 0) {
                          setState(() => _invalid = true);
                          return;
                        }
                        unawaited(_save(ttl));
                      },
                child: Text(l10n.desktopSafeSearchTtlSave),
              ),
            ],
          ),
          if (_invalid) ...[
            const SizedBox(height: 6),
            Text(
              l10n.desktopSafeSearchTtlInvalid,
              style: DashboardText.label(
                context,
                color: context.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
