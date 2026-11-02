/// The query log's own settings: whether anything is recorded, how much is kept in memory, whether
/// history is written to disk and for how long, and whether client details are stored.
///
/// The behaviour is the old desktop console's `QueryLogConfigCard.vue`: the three switches apply
/// immediately (and flip back if the service rejects them), the two numbers travel with the save
/// button, and the on-disk directory is read-only because it belongs to the service's data layout.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_api_models.dart';
import 'package:diting_desktop/data/api/desktop_log_providers.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Wide enough for `10000` and its label; two of them share a row in a desktop window.
const double _numberWidth = 190;

class LogConfigCard extends ConsumerStatefulWidget {
  const LogConfigCard({super.key});

  @override
  ConsumerState<LogConfigCard> createState() => _LogConfigCardState();
}

class _LogConfigCardState extends ConsumerState<LogConfigCard> {
  /// The two numbers as typed. Empty until the first answer arrives, which is what tells the form
  /// it has values to show; a later save must not overwrite what is being typed.
  String _maxEntries = '';
  String _retentionDays = '';
  bool _invalid = false;

  Future<void> _save(DesktopQueryLogConfig next) async {
    final l10n = context.l10n;
    final error = await ref.read(desktopLogConfigProvider.notifier).save(next);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          error == null
              ? l10n.desktopLogConfigSaved
              : l10n.desktopActionFailed(error.message),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// The button's job: the typed numbers, or a note that they are not usable. Switches keep their
  /// own immediate path and send the numbers the service already holds.
  void _submitNumbers(DesktopQueryLogConfig config) {
    final maxEntries = int.tryParse(_maxEntries);
    final retentionDays = int.tryParse(_retentionDays);
    final valid =
        maxEntries != null &&
        maxEntries > 0 &&
        retentionDays != null &&
        retentionDays > 0;
    if (!valid) {
      setState(() => _invalid = true);
      return;
    }
    setState(() => _invalid = false);
    unawaited(
      _save(
        config.copyWith(
          maxEntries: maxEntries,
          retentionDays: retentionDays,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(desktopLogConfigProvider);
    final config = state.config;
    if (config != null && _maxEntries.isEmpty) {
      _maxEntries = '${config.maxEntries}';
      _retentionDays = '${config.retentionDays}';
    }
    return DashboardCard(
      semanticLabel: l10n.desktopLogConfigTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.sliders,
            title: l10n.desktopLogConfigTitle,
            trailing: [
              if (state.saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              else
                DashboardIconButton(
                  glyph: AppGlyphs.check,
                  tooltip: l10n.desktopLogConfigSave,
                  onPressed: config == null
                      ? null
                      : () => _submitNumbers(config),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (config == null)
            _Unavailable(
              isLoading: state.isLoading,
              error: state.error?.message,
              onRetry: ref.read(desktopLogConfigProvider.notifier).reload,
            )
          else
            _form(context, config, state.error),
        ],
      ),
    );
  }

  Widget _form(
    BuildContext context,
    DesktopQueryLogConfig config,
    DesktopApiException? error,
  ) {
    final l10n = context.l10n;
    void save(DesktopQueryLogConfig next) => unawaited(_save(next));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        _ToggleRow(
          title: l10n.desktopLogConfigEnabled,
          body: l10n.desktopLogConfigEnabledBody,
          value: config.enabled,
          onChanged: (value) => save(config.copyWith(enabled: value)),
        ),
        if (config.enabled) ...[
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              SizedBox(
                width: _numberWidth,
                child: TextFormField(
                  initialValue: _maxEntries,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: l10n.desktopLogConfigMaxEntries,
                  ),
                  style: AppTextStyle.callout.of(context),
                  onChanged: (value) => _maxEntries = value,
                ),
              ),
              SizedBox(
                width: _numberWidth,
                child: TextFormField(
                  initialValue: _retentionDays,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: l10n.desktopLogConfigRetentionDays,
                  ),
                  style: AppTextStyle.callout.of(context),
                  onChanged: (value) => _retentionDays = value,
                ),
              ),
            ],
          ),
          if (_invalid)
            Text(
              l10n.desktopLogConfigInvalid,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.label(
                context,
                color: context.colorScheme.error,
              ),
            ),
          _ToggleRow(
            title: l10n.desktopLogConfigFile,
            body: l10n.desktopLogConfigFileBody,
            value: config.fileEnabled,
            onChanged: (value) => save(config.copyWith(fileEnabled: value)),
          ),
          _ToggleRow(
            title: l10n.desktopLogConfigClients,
            body: l10n.desktopLogConfigClientsBody,
            value: config.logClients,
            onChanged: (value) => save(config.copyWith(logClients: value)),
          ),
          if (config.dataDir.isNotEmpty)
            Text(
              l10n.desktopLogConfigDataDir(config.dataDir),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.label(context),
            ),
        ],
        if (error != null)
          Text(
            l10n.desktopActionFailed(error.message),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(
              context,
              color: context.colorScheme.error,
            ),
          ),
      ],
    );
  }
}

/// One switch with its own explanation. The row owns the tap — the switch is pointer-transparent —
/// so there is one target per boolean, and the row keeps its ripple and focus ring.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.body,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String body;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      semanticLabel: title,
      onTap: () => onChanged(!value),
      child: Row(
        spacing: 10,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.rowTitle(context),
                ),
                Text(
                  body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.label(context),
                ),
              ],
            ),
          ),
          IgnorePointer(
            child: DashboardSwitch(
              value: value,
              onChanged: onChanged,
              semanticLabel: title,
            ),
          ),
        ],
      ),
    );
  }
}

/// Before the first answer, and after a failed one: the form needs real values, so it is not drawn
/// with guesses.
class _Unavailable extends StatelessWidget {
  const _Unavailable({
    required this.isLoading,
    required this.error,
    required this.onRetry,
  });

  final bool isLoading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CommonCircleLoading(size: 20)),
      );
    }
    return Row(
      spacing: 8,
      children: [
        GlyphIcon(
          AppGlyphs.warning,
          size: 18,
          color: context.colorScheme.warning,
        ),
        Expanded(
          child: Text(
            '${l10n.desktopLogConfigLoadFailed} · ${error ?? ''}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.rowTitle(context),
          ),
        ),
        TextButton(onPressed: onRetry, child: Text(l10n.desktopRetry)),
      ],
    );
  }
}
