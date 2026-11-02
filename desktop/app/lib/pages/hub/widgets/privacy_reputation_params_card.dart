/// The reputation lookup parameters: timeout, cache size and cache lifetime.
///
/// The old desktop console's `SafeBrowsingCard.vue` keeps these three numbers under the switch; here
/// they are their own card so the lookup's counters do not share a card with a form. They are a draft
/// that saves with the button, and the service's normalised answer is adopted afterwards.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_privacy_models.dart';
import 'package:diting_desktop/data/api/desktop_reputation_providers.dart';
import 'package:diting_desktop/pages/hub/widgets/privacy_common.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const double _fieldWidth = 170;

class PrivacyReputationParamsCard extends ConsumerStatefulWidget {
  const PrivacyReputationParamsCard({super.key});

  @override
  ConsumerState<PrivacyReputationParamsCard> createState() =>
      _PrivacyReputationParamsCardState();
}

class _PrivacyReputationParamsCardState
    extends ConsumerState<PrivacyReputationParamsCard> {
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

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  void _submit(DesktopSafeBrowsing data) {
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
      savePrivacySetting(
        context,
        ref,
        () async {
          final error = await ref
              .read(desktopReputationProvider.notifier)
              .save({
                'timeoutMs': timeout,
                'cacheSize': cacheSize,
                'cacheTTLSeconds': cacheTtl,
              });
          if (error == null && mounted) setState(() => _dirty = false);
          return error;
        },
        l10n.desktopReputationParamsSaved,
      ),
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
      semanticLabel: l10n.desktopReputationParamsTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.speed,
            title: l10n.desktopReputationParamsTitle,
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
            l10n.desktopReputationFooter,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _NumberField(
                label: l10n.desktopReputationTimeout,
                controller: _timeout,
                enabled: data != null && data.enabled && !saving,
                onChanged: _markDirty,
              ),
              _NumberField(
                label: l10n.desktopReputationCacheSize,
                controller: _cacheSize,
                enabled: data != null && data.enabled && !saving,
                onChanged: _markDirty,
              ),
              _NumberField(
                label: l10n.desktopReputationCacheTtl,
                controller: _cacheTtl,
                enabled: data != null && data.enabled && !saving,
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
              onPressed: data != null && data.enabled && !saving
                  ? () => _submit(data)
                  : null,
              child: Text(l10n.desktopReputationParamsSave),
            ),
          ),
        ],
      ),
    );
  }
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
