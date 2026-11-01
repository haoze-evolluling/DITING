/// The live query stream: what the service pushes over `/api/v1/events`, filtered on the client
/// because it is a bounded buffer, not a search.
///
/// The behaviour is the old desktop console's `LiveQueryPanel.vue`: a scrolling buffer of at most
/// 500 queries, newest first, with pause and clear, a free-text filter, a record-type filter, a
/// response-code filter and a "blocked only" toggle. The counts at the bottom are counted over the
/// buffer that is on screen and are labelled as such — they are not the service's 24-hour totals,
/// which the summary card above already shows.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_api_models.dart';
import 'package:diting/desktop/data/api/desktop_event_client.dart';
import 'package:diting/desktop/data/api/desktop_live_providers.dart';
import 'package:diting/desktop/pages/home/desktop_format.dart';
import 'package:diting/desktop/pages/logs/log_format.dart';
import 'package:diting/desktop/widgets/desktop_picker.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Tall enough for a handful of rows at any text scale; the list scrolls inside it so the cards
/// below stay where they are while queries keep arriving.
const double _listHeight = 320;

/// Width of the search field in the controls row; the pickers take what is left.
const double _searchWidth = 240;

/// The response codes the console filters on, in the order it offers them.
const List<String> _rcodes = ['NOERROR', 'NXDOMAIN', 'SERVFAIL'];

class LogLivePanel extends ConsumerStatefulWidget {
  const LogLivePanel({super.key});

  @override
  ConsumerState<LogLivePanel> createState() => _LogLivePanelState();
}

class _LogLivePanelState extends ConsumerState<LogLivePanel> {
  final _search = TextEditingController();

  /// View state, not data: filtering 500 rows needs no provider, and it must not survive a
  /// rebuild of the branch.
  String _needle = '';
  String _qtype = '';
  String _rcode = '';
  bool _onlyBlocked = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The same three conditions the console applies: text over domain and client, one record type,
  /// one response code, plus the blocked-only switch.
  bool _matches(DesktopLiveQuery entry) {
    if (_onlyBlocked && !entry.blocked) return false;
    if (_qtype.isNotEmpty && entry.qtype != _qtype) return false;
    if (_rcode.isNotEmpty && entry.responseCode != _rcode) return false;
    if (_needle.isEmpty) return true;
    return entry.domain.toLowerCase().contains(_needle) ||
        entry.clientIp.toLowerCase().contains(_needle) ||
        entry.clientName.toLowerCase().contains(_needle);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final live = ref.watch(desktopLiveProvider);
    final visible = live.entries.where(_matches).toList();

    return DashboardCard(
      semanticLabel: l10n.desktopLiveTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.requests,
            title: l10n.desktopLiveTitle,
            leading: [_ConnectionChip(live: live)],
          ),
          const SizedBox(height: 12),
          _controls(context, live),
          const SizedBox(height: 8),
          _list(context, live, visible),
          const SizedBox(height: 10),
          _footer(context, live, visible),
        ],
      ),
    );
  }

  Widget _controls(BuildContext context, DesktopLiveState live) {
    final l10n = context.l10n;
    final search = SearchField(
      controller: _search,
      hintText: l10n.desktopLiveSearchHint,
      onChanged: (value) => setState(() => _needle = value.trim().toLowerCase()),
    );
    final controls = <Widget>[
      DesktopPicker(
        glyph: AppGlyphs.sort,
        semanticLabel: l10n.logsRecordType,
        label: _qtype.isEmpty ? l10n.desktopLogAllTypes : _qtype,
        active: _qtype.isNotEmpty,
        items: [
          CommonPopupMenuItem(
            label: l10n.desktopLogAllTypes,
            checked: _qtype.isEmpty,
            onPressed: () => setState(() => _qtype = ''),
          ),
          for (final type in desktopLogQTypes)
            CommonPopupMenuItem(
              label: type,
              checked: type == _qtype,
              onPressed: () => setState(() => _qtype = type),
            ),
        ],
      ),
      DesktopPicker(
        glyph: AppGlyphs.status,
        semanticLabel: l10n.obsStatus,
        label: _rcode.isEmpty ? l10n.commonAll : _rcode,
        active: _rcode.isNotEmpty,
        items: [
          CommonPopupMenuItem(
            label: l10n.commonAll,
            checked: _rcode.isEmpty,
            onPressed: () => setState(() => _rcode = ''),
          ),
          for (final rcode in _rcodes)
            CommonPopupMenuItem(
              label: rcode,
              checked: rcode == _rcode,
              onPressed: () => setState(() => _rcode = rcode),
            ),
        ],
      ),
      _BlockedOnlyToggle(
        value: _onlyBlocked,
        onPressed: () => setState(() => _onlyBlocked = !_onlyBlocked),
      ),
      TextButton(
        onPressed: ref.read(desktopLiveProvider.notifier).togglePaused,
        child: Text(live.paused ? l10n.desktopLiveResume : l10n.desktopLivePause),
      ),
      TextButton(
        onPressed: live.entries.isEmpty
            ? null
            : ref.read(desktopLiveProvider.notifier).clear,
        child: Text(l10n.desktopLiveClear),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        // The pickers and buttons need room of their own; below that the search field takes a
        // whole row and the controls wrap under it.
        final inline = constraints.maxWidth >= 720;
        return Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(width: inline ? _searchWidth : constraints.maxWidth, child: search),
            ...controls,
          ],
        );
      },
    );
  }

  Widget _list(
    BuildContext context,
    DesktopLiveState live,
    List<DesktopLiveQuery> visible,
  ) {
    final l10n = context.l10n;
    if (visible.isEmpty) {
      return SizedBox(
        height: _listHeight,
        child: NullStatus(
          illustration: NullStatusIllustration.requests,
          label: live.entries.isEmpty
              ? l10n.desktopLiveEmpty
              : l10n.obsNoMatchingRequests,
          description: live.entries.isEmpty && !live.connected
              ? l10n.desktopLiveDisconnectedBody
              : null,
        ),
      );
    }
    return SizedBox(
      height: _listHeight,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(height: 4),
        itemBuilder: (context, index) => _LiveRow(entry: visible[index]),
      ),
    );
  }

  /// Counted over the buffer on screen, which is what the labels say.
  Widget _footer(
    BuildContext context,
    DesktopLiveState live,
    List<DesktopLiveQuery> visible,
  ) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final blocked = visible.where((entry) => entry.blocked).length;
    final succeeded = visible.where((entry) => entry.success).length;
    final rate = visible.isEmpty ? 0.0 : succeeded / visible.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        StatStrip(
          padding: EdgeInsets.zero,
          stats: [
            StatItem(
              label: l10n.desktopLiveCaptured,
              value: dashboardCount(visible.length),
            ),
            StatItem(
              label: l10n.desktopLiveBlocked,
              value: dashboardCount(blocked),
              color: colorScheme.error,
            ),
            StatItem(
              label: l10n.desktopLiveSuccessRate,
              value: visible.isEmpty ? desktopNoValue : desktopPercent(rate),
              color: colorScheme.success,
            ),
          ],
        ),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: Text(
                l10n.desktopLiveShown('${visible.length}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashboardText.label(context),
              ),
            ),
            Flexible(
              child: Text(
                l10n.desktopLiveBufferNote('$desktopLiveBufferSize'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: DashboardText.label(context),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Whether the socket is up, or the list is frozen on purpose. Three states, because "listening"
/// over a socket that is not connected would be a claim the app cannot back.
class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.live});

  final DesktopLiveState live;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (label, tone) = live.paused
        ? (l10n.desktopLivePaused, DashboardChipTone.warn)
        : live.connected
        ? (l10n.desktopLiveConnected, DashboardChipTone.ok)
        : (l10n.desktopLiveDisconnected, DashboardChipTone.warn);
    return DashboardChip(label: label, tone: tone, dot: true);
  }
}

class _BlockedOnlyToggle extends StatelessWidget {
  const _BlockedOnlyToggle({required this.value, required this.onPressed});

  final bool value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = value
        ? context.colorScheme.error
        : context.colorScheme.onSurfaceVariant;
    return TextButton(
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          GlyphIcon(
            value ? AppGlyphs.check : AppGlyphs.block,
            size: 16,
            color: color,
          ),
          Text(
            context.l10n.desktopLiveOnlyBlocked,
            style: AppTextStyle.callout.of(context).copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// One pushed query: the disposition, the record type, the name, the latency, and who asked.
class _LiveRow extends StatelessWidget {
  const _LiveRow({required this.entry});

  final DesktopLiveQuery entry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final (statusColor, statusLabel) = switch (entry.status) {
      DesktopLiveStatus.passed => (colorScheme.onSurfaceVariant, l10n.logPassed),
      DesktopLiveStatus.blocked => (colorScheme.error, l10n.logBlocked),
      DesktopLiveStatus.cached => (colorScheme.success, l10n.logCacheHits),
      DesktopLiveStatus.stale => (colorScheme.warning, l10n.desktopLiveStale),
      DesktopLiveStatus.error => (colorScheme.error, l10n.logFailed),
    };
    final label = DashboardText.label(context);
    return DashboardBlock(
      color: entry.blocked
          ? colorScheme.error.withValues(alpha: 0.06)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 2,
        children: [
          Row(
            spacing: 8,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: ShapeDecoration(
                  color: statusColor,
                  shape: const CircleBorder(),
                ),
              ),
              Text(statusLabel, maxLines: 1, style: label.copyWith(color: statusColor)),
              if (entry.qtype.isNotEmpty)
                DashboardChip(label: entry.qtype, tone: DashboardChipTone.idle),
              Expanded(
                child: Text(
                  entry.displayDomain,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.rowTitle(context).copyWith(
                    decoration: entry.blocked ? TextDecoration.lineThrough : null,
                    decorationColor: colorScheme.error,
                  ),
                ),
              ),
              Text(
                desktopLatency(entry.durationMs),
                maxLines: 1,
                style: label.copyWith(
                  color: entry.durationMs > 100 ? colorScheme.warning : null,
                ),
              ),
            ],
          ),
          Row(
            spacing: 6,
            children: [
              Expanded(
                child: Text(
                  entry.clientName.isEmpty
                      ? entry.clientIp
                      : '${entry.clientName} (${entry.clientIp})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: label,
                ),
              ),
              if (entry.blocked && entry.blockReason.isNotEmpty)
                Flexible(
                  child: Text(
                    entry.blockReason,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: label.copyWith(color: colorScheme.error),
                  ),
                ),
              Text(desktopClock(entry.timestamp), maxLines: 1, style: label),
            ],
          ),
        ],
      ),
    );
  }
}
