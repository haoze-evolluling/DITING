import 'dart:async';

import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/data/server/server_runtime_models.dart';
import 'package:diting_android/pages/server/server_common.dart';
import 'package:diting_android/pages/server/server_home_style.dart';
import 'package:diting_android/routes/server_routes.dart';
import 'package:diting_android/widgets/icon_badge.dart';
import 'package:diting_android/widgets/status_pill.dart';
import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class ServerStatusOverview extends StatelessWidget {
  const ServerStatusOverview({
    super.key,
    required this.status,
    required this.config,
  });

  final ServerStatus status;
  final ServerConfig config;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = context.l10n;
    final running = status.running;
    final address = status.addresses.isEmpty
        ? '0.0.0.0:${status.port}'
        : status.addresses.join('  ·  ');
    final state = running
        ? l10n.serverListening
        : status.stopping
        ? l10n.stateStopping
        : status.starting
        ? l10n.serverStarting
        : l10n.serverStopped;
    final dotColor = running
        ? scheme.success
        : status.isBusy
        ? scheme.warning
        : status.error != null
        ? scheme.error
        : scheme.onSurfaceVariant;
    return ServerSectionCard(
      onPressed: () => context.push(ServerRoutes.settings),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Row(
            spacing: 8,
            children: [
              Icon(
                TablerIcons.activity,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              Expanded(
                child: Text(
                  l10n.serverStatusTitle,
                  style: AppTextRole.rowTitle.of(context),
                ),
              ),
              MetaChip(
                label: status.root
                    ? l10n.serverRootMode
                    : l10n.serverNonRootMode,
              ),
              const Icon(TablerIcons.chevron_right, size: 17),
            ],
          ),
          Row(
            spacing: 12,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 5,
                  children: [
                    Row(
                      spacing: 7,
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: ShapeDecoration(
                            color: dotColor,
                            shape: AppShape.standard,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            state,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextRole.sectionLabel
                                .of(context)
                                .copyWith(
                                  color: running
                                      ? scheme.onSurface
                                      : scheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextRole.supportingText
                          .of(context)
                          .copyWith(
                            color: scheme.onSurfaceVariant,
                            fontFeatures: appTabularFigures,
                          ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                spacing: 2,
                children: [
                  _LiveUptime(status: status),
                  Text(
                    l10n.serverUptime,
                    style: AppTextRole.caption
                        .of(context)
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusPill(
                label: l10n.serverUpstreamShort(
                  config.upstream.providers.length,
                ),
                color: scheme.primary,
                alpha: 0.11,
                foregroundColor: scheme.primary,
                leading: TablerIcons.cloud_upload,
                leadingSize: 13,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              ),
              StatusPill(
                label: config.filter.enabled
                    ? l10n.serverFilterOn
                    : l10n.serverFilterOff,
                color: config.filter.enabled
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
                alpha: 0.08,
                foregroundColor: config.filter.enabled
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
                leading: TablerIcons.shield,
                leadingSize: 13,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              ),
              StatusPill(
                label: l10n.serverCacheEntriesShort(config.cache.maxEntries),
                color: scheme.onSurfaceVariant,
                alpha: 0.10,
                leading: TablerIcons.database,
                leadingSize: 13,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              ),
            ],
          ),
          Text(
            l10n.serverClientHint(status.port),
            style: AppTextRole.supportingText
                .of(context)
                .copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _LiveUptime extends StatefulWidget {
  const _LiveUptime({required this.status});

  final ServerStatus status;

  @override
  State<_LiveUptime> createState() => _LiveUptimeState();
}

class _LiveUptimeState extends State<_LiveUptime>
    with PageVisibilityMixin<_LiveUptime> {
  Timer? _ticker;
  bool _visible = false;

  @override
  void onPageVisibilityChanged(bool visible) {
    _visible = visible;
    _syncTicker();
  }

  @override
  void didUpdateWidget(_LiveUptime oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  void _syncTicker() {
    final counting = widget.status.running && widget.status.startedAt != null;
    if (_visible && counting) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uptime = _uptimeOf(widget.status);
    return Text(
      uptime == null ? '—' : _uptimeLabel(uptime, context.l10n),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.end,
      style: AppTextRole.metricSmall
          .of(context)
          .toTabular
          .copyWith(color: context.colorScheme.onSurface),
    );
  }
}

Duration? _uptimeOf(ServerStatus status) {
  final started = status.startedAt;
  if (!status.running || started == null) return null;
  final elapsed = DateTime.now().difference(started);
  return elapsed.isNegative ? Duration.zero : elapsed;
}

String _uptimeLabel(Duration uptime, AppL10n l10n) {
  final hours = uptime.inHours;
  final minutes = uptime.inMinutes % 60;
  final seconds = uptime.inSeconds % 60;
  if (hours > 0) {
    return '${l10n.durationHours(hours)}'
        '${l10n.durationMinutes(minutes)}';
  }
  if (minutes > 0) {
    return '${l10n.durationMinutes(minutes)}'
        '${l10n.durationSeconds(seconds)}';
  }
  return l10n.durationSeconds(seconds);
}

class ServerQuickActions extends StatelessWidget {
  const ServerQuickActions({super.key, required this.config});

  final ServerConfig config;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final actions = [
      (
        glyph: TablerIcons.cloud_upload,
        title: l10n.serverUpstream,
        subtitle: config.upstream.providers.isEmpty
            ? l10n.serverUpstreamRequired
            : l10n.serverUpstreamShort(config.upstream.providers.length),
        path: ServerRoutes.upstream,
      ),
      (
        glyph: TablerIcons.filter,
        title: l10n.serverFilterTitle,
        subtitle: config.filter.enabled
            ? l10n.serverFilterOn
            : l10n.serverFilterOff,
        path: ServerRoutes.filter,
      ),
      (
        glyph: TablerIcons.logs,
        title: l10n.serverLogsTitle,
        subtitle: l10n.serverLogDays(config.queryLog.retentionDays),
        path: ServerRoutes.queryLog,
      ),
    ];
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return ServerSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Row(
            spacing: 8,
            children: [
              const Icon(TablerIcons.puzzle, size: 18),
              Expanded(
                child: Text(
                  l10n.serverQuickActions,
                  style: AppTextRole.rowTitle.of(context),
                ),
              ),
            ],
          ),
          if (scale >= 1.3)
            Column(
              spacing: 8,
              children: [
                for (final action in actions)
                  _QuickActionTile(
                    glyph: action.glyph,
                    title: action.title,
                    subtitle: action.subtitle,
                    onTap: () => context.push(action.path),
                    stacked: false,
                  ),
              ],
            )
          else
            Row(
              spacing: 4,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final action in actions)
                  Expanded(
                    child: _QuickActionTile(
                      glyph: action.glyph,
                      title: action.title,
                      subtitle: action.subtitle,
                      onTap: () => context.push(action.path),
                      stacked: true,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.glyph,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.stacked,
  });

  final IconData glyph;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Material(
      color: Colors.transparent,
      shape: AppShape.standard,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: AppShape.standard,
        child: stacked
            ? Padding(
                padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconBadge(
                      glyph: glyph,
                      size: 38,
                      glyphSize: 19,
                      color: ServerHomeColors.accentWash(context),
                      foregroundColor: scheme.primary,
                    ),
                    const SizedBox(height: 7),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTextRole.sectionLabel.of(context),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTextRole.micro
                          .of(context)
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  spacing: 10,
                  children: [
                    IconBadge(
                      glyph: glyph,
                      size: 36,
                      glyphSize: 18,
                      color: ServerHomeColors.accentWash(context),
                      foregroundColor: scheme.primary,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        spacing: 2,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextRole.sectionLabel.of(context),
                          ),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextRole.micro
                                .of(context)
                                .copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const Icon(TablerIcons.chevron_right, size: 16),
                  ],
                ),
              ),
      ),
    );
  }
}
