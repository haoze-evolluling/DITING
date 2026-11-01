/// The reputation lookups: malicious-site checking, parental control and their shared query
/// parameters.
///
/// The old desktop console's `SafeBrowsingCard.vue` and `ParentalControlCard.vue` are the blueprint.
/// The two switches save one field each; timeout, cache size and cache lifetime are a draft that
/// saves with its button, and the service's normalised answer is adopted directly.
library;

import 'dart:async';

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_privacy_models.dart';
import 'package:diting/desktop/data/api/desktop_reputation_providers.dart';
import 'package:diting/desktop/pages/hub/widgets/filter_common.dart';
import 'package:diting/desktop/widgets/desktop_feedback.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const double _fieldWidth = 170;

class PrivacyReputationCard extends ConsumerStatefulWidget {
  const PrivacyReputationCard({super.key});

  @override
  ConsumerState<PrivacyReputationCard> createState() =>
      _PrivacyReputationCardState();
}

class _PrivacyReputationCardState
    extends ConsumerState<PrivacyReputationCard> {
  final _timeout = TextEditingController();
  final _cacheSize = TextEditingController();
  final _cacheTtl = TextEditingController();
  DesktopSafeBrowsing? _adopted;
  bool _dirty = false;
  bool _invalid = false;

  @override
  void dispose() {
    _timeout.dispose();
    _cacheSize.dispose();
    _cacheTtl.dispose();
    super.dispose();
  }

  void _adopt(DesktopSafeBrowsing data) {
    if (identical(_adopted, data)) return;
    _adopted = data;
    if (_dirty) return;
    _timeout.text = '${data.effectiveTimeoutMs}';
    _cacheSize.text = '${data.cacheSize}';
    _cacheTtl.text = '${data.effectiveCacheTtl}';
  }

  Future<void> _save(
    Map<String, Object?> patch, {
    required String success,
    bool fromForm = false,
  }) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopReputationProvider.notifier)
        .save(patch);
    if (!mounted) return;
    if (error == null && fromForm) setState(() => _dirty = false);
    showDesktopMessage(
      context,
      error == null ? success : l10n.desktopPrivacySaveFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(desktopReputationProvider);
    final data = state.data;
    if (data != null) _adopt(data);
    final saving = state.saving;
    return DashboardCard(
      semanticLabel: l10n.desktopReputationTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.gavel,
            title: l10n.desktopReputationTitle,
            leading: [
              if (data != null)
                DashboardChip(
                  label: data.enabled
                      ? l10n.desktopReputationOn
                      : l10n.desktopReputationOff,
                  tone: data.enabled
                      ? DashboardChipTone.ok
                      : DashboardChipTone.idle,
                  dot: data.enabled,
                ),
            ],
            trailing: [
              if (saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              else if (data != null)
                DashboardSwitch(
                  value: data.enabled,
                  semanticLabel: l10n.desktopReputationTitle,
                  onChanged: (value) => unawaited(
                    _save(
                      {'enabled': value},
                      success: value
                          ? l10n.desktopReputationOnMessage
                          : l10n.desktopReputationOffMessage,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopReputationBody,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 10),
          if (data == null)
            _Unavailable(
              loading: state.isLoading,
              onRetry: ref.read(desktopReputationProvider.notifier).reload,
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final metrics = [
                  FilterMetric(
                    label: l10n.desktopReputationLookups,
                    value: dashboardCount(data.lookups),
                  ),
                  FilterMetric(
                    label: l10n.desktopReputationBlocked,
                    value: dashboardCount(data.blocked),
                  ),
                  FilterMetric(
                    label: l10n.desktopReputationHitRate,
                    value: data.hitRate == null
                        ? '—'
                        : '${(data.hitRate! * 100).round()}',
                    unit: data.hitRate == null ? null : '%',
                  ),
                  FilterMetric(
                    label: l10n.desktopReputationFailures,
                    value: dashboardCount(data.failures),
                  ),
                  FilterMetric(
                    label: l10n.desktopReputationAnswer,
                    value: desktopReputationAnswer(context, data),
                  ),
                ];
                if (constraints.maxWidth < 620) {
                  return Wrap(spacing: 20, runSpacing: 10, children: metrics);
                }
                return Row(
                  spacing: 14,
                  children: [
                    for (final metric in metrics) Expanded(child: metric),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _NumberField(
                  label: l10n.desktopReputationTimeout,
                  controller: _timeout,
                  enabled: data.enabled && !saving,
                  onChanged: _markDirty,
                ),
                _NumberField(
                  label: l10n.desktopReputationCacheSize,
                  controller: _cacheSize,
                  enabled: data.enabled && !saving,
                  onChanged: _markDirty,
                ),
                _NumberField(
                  label: l10n.desktopReputationCacheTtl,
                  controller: _cacheTtl,
                  enabled: data.enabled && !saving,
                  onChanged: _markDirty,
                ),
              ],
            ),
            if (_invalid) ...[
              const SizedBox(height: 6),
              Text(
                l10n.desktopReputationParamsInvalid,
                style: DashboardText.label(
                  context,
                  color: context.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.tonal(
                onPressed: data.enabled && !saving
                    ? () => _submitParams()
                    : null,
                child: Text(l10n.desktopReputationParamsSave),
              ),
            ),
            const SizedBox(height: 10),
            FilterToggleRow(
              title: l10n.desktopParentalTitle,
              body: l10n.desktopParentalBody,
              value: data.parentalEnabled,
              warning: data.enabled ? null : l10n.desktopParentalWarning,
              onChanged: saving
                  ? null
                  : (value) => unawaited(
                      _save(
                        {'parentalEnabled': value},
                        success: value
                            ? l10n.desktopParentalOn
                            : l10n.desktopParentalOff,
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.desktopReputationFooter,
              style: DashboardText.label(context),
            ),
          ],
        ],
      ),
    );
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  void _submitParams() {
    final l10n = context.l10n;
    final timeout = int.tryParse(_timeout.text);
    final cacheSize = int.tryParse(_cacheSize.text);
    final cacheTtl = int.tryParse(_cacheTtl.text);
    if (timeout == null ||
        timeout <= 0 ||
        cacheSize == null ||
        cacheSize < 0 ||
        cacheTtl == null ||
        cacheTtl <= 0) {
      setState(() => _invalid = true);
      return;
    }
    setState(() => _invalid = false);
    unawaited(
      _save(
        {
          'timeoutMs': timeout,
          'cacheSize': cacheSize,
          'cacheTTLSeconds': cacheTtl,
        },
        success: l10n.desktopReputationParamsSaved,
        fromForm: true,
      ),
    );
  }
}

String desktopReputationAnswer(BuildContext context, DesktopSafeBrowsing data) {
  final l10n = context.l10n;
  return switch (data.blockMode) {
    'nxdomain' => 'NXDOMAIN',
    'refused' => 'REFUSED',
    _ => data.blockingIpv4.isEmpty
        ? l10n.desktopReputationAnswerNullIp
        : data.blockingIpv4,
  };
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _fieldWidth,
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label),
        style: AppTextStyle.callout.of(context),
        onChanged: (_) => onChanged(),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.loading, required this.onRetry});

  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CommonCircleLoading(size: 20)),
      );
    }
    return FilledButton.tonal(
      onPressed: onRetry,
      child: Text(l10n.desktopRetry),
    );
  }
}
