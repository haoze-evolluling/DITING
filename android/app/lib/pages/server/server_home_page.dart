import 'dart:async';

import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/data/server/server_runtime_models.dart';
import 'package:diting_android/pages/home/widgets/home_power_button.dart';
import 'package:diting_android/pages/server/server_common.dart';
import 'package:diting_android/routes/server_routes.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/widgets/icon_badge.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/routes/branches.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class ServerHomePage extends ConsumerStatefulWidget {
  const ServerHomePage({super.key});

  @override
  ConsumerState<ServerHomePage> createState() => _ServerHomePageState();
}

class _ServerHomePageState extends ConsumerState<ServerHomePage>
    with PageVisibilityMixin<ServerHomePage> {
  Timer? _timer;
  bool _busy = false;

  @override
  void onPageVisibilityChanged(bool visible) {
    _timer?.cancel();
    _timer = visible
        ? Timer.periodic(const Duration(seconds: 5), (_) {
            if (!_busy) {
              ref.read(serverControllerProvider.notifier).refreshLive();
            }
          })
        : null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _toggle(ServerStatus status) async {
    if (_busy) return;
    if (status.active) {
      await _stop();
    } else {
      final preferRoot =
          ref.read(serverControllerProvider).value?.config.listen.root ?? true;
      await _start(preferRoot: preferRoot);
    }
  }

  Future<void> _start({required bool preferRoot}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(serverControllerProvider.notifier)
          .start(preferRoot: preferRoot);
    } catch (error) {
      if (mounted) showAppSnack(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(serverControllerProvider.notifier).stop();
    } catch (error) {
      if (mounted) showAppSnack(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(serverControllerProvider);
    final value = snapshot.value;
    return CommonScaffold(
      title: context.l10n.workModeServerTitle,
      actions: [
        IconButton(
          tooltip: context.l10n.homeSwitchWorkMode,
          onPressed: () => context.push(Routes.modeSelect),
          icon: const GlyphIcon(AppGlyphs.swap),
        ),
      ],
      body: PageBody(
        children: [
          if (snapshot.hasError && value == null)
            ServerErrorCard(
              message: snapshot.error.toString(),
              onRetry: () =>
                  ref.read(serverControllerProvider.notifier).refresh(),
            )
          else if (value == null)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CommonCircleLoading()),
            )
          else ...[
            if (value.status.error case final error?)
              ServerErrorCard(
                message: error,
                retryLabel: _canFallbackTo1053(value.status)
                    ? context.l10n.serverRetryPort1053
                    : null,
                onRetry: _canFallbackTo1053(value.status)
                    ? () => _start(preferRoot: false)
                    : () => _toggle(value.status),
              ),
            HomePowerButton(
              state: serverPowerState(value.status),
              onPressed: () => _toggle(value.status),
              runningLabel: context.l10n.serverStop,
              stoppedLabel: context.l10n.serverStart,
              busyLabel: context.l10n.serverStarting,
            ),
            _ListenCard(status: value.status),
            _StatsCard(stats: value.stats),
            _ConfigSummary(config: value.config),
            _RecentQueries(running: value.status.running),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

bool _canFallbackTo1053(ServerStatus status) =>
    status.root && status.error?.contains('53') == true;

class _ListenCard extends StatelessWidget {
  const _ListenCard({required this.status});

  final ServerStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final address = status.addresses.isEmpty
        ? '0.0.0.0:${status.port}'
        : status.addresses.join('  ·  ');
    return ServerSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Row(
            spacing: 12,
            children: [
              IconBadge(
                glyph: AppGlyphs.dns,
                size: 42,
                glyphSize: 22,
                color: status.running
                    ? scheme.primary.withValues(alpha: 0.14)
                    : scheme.surfaceContainerHigh,
                foregroundColor: status.running
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      status.running
                          ? context.l10n.serverListening
                          : status.starting
                          ? context.l10n.serverStarting
                          : context.l10n.serverStopped,
                      style: context.listTitleStyle,
                    ),
                    Text(
                      address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.listSubtitleStyle.copyWith(
                        fontFeatures: appTabularFigures,
                      ),
                    ),
                  ],
                ),
              ),
              MetaChip(
                label: status.root
                    ? context.l10n.serverRootMode
                    : context.l10n.serverNonRootMode,
              ),
            ],
          ),
          Text(
            context.l10n.serverClientHint(status.port),
            style: context.listSubtitleStyle,
          ),
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats});

  final ServerStats stats;

  @override
  Widget build(BuildContext context) {
    return ServerSectionCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: StatStrip(
        stats: [
          StatItem(
            label: context.l10n.serverQueries,
            value: serverCount(stats.queries),
          ),
          StatItem(
            label: context.l10n.serverBlocked,
            value: serverCount(stats.blocked),
          ),
          StatItem(
            label: context.l10n.serverBlockRate,
            value: serverPercent(stats.blockedRate),
          ),
          StatItem(
            label: context.l10n.serverCacheHit,
            value: serverPercent(stats.cacheHitRate),
          ),
        ],
      ),
    );
  }
}

class _ConfigSummary extends StatelessWidget {
  const _ConfigSummary({required this.config});

  final ServerConfig config;

  @override
  Widget build(BuildContext context) {
    final upstream = config.upstream.providers.isEmpty
        ? '—'
        : config.upstream.providers.map((item) => item.id).join(' · ');
    return Column(
      children: [
        ServerSectionCard(
          onPressed: () => context.push(ServerRoutes.upstream),
          child: _SummaryRow(
            glyph: AppGlyphs.upstream,
            title: context.l10n.serverUpstream,
            value: upstream,
          ),
        ),
        ServerSectionCard(
          onPressed: () => context.push(ServerRoutes.filter),
          child: _SummaryRow(
            glyph: AppGlyphs.rules,
            title: context.l10n.serverFilter,
            value: config.filter.enabled
                ? context.l10n.serverFilterOn
                : context.l10n.serverFilterOff,
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.glyph,
    required this.title,
    required this.value,
  });

  final Glyph glyph;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 12,
      children: [
        GlyphIcon(glyph, size: 20, color: context.colorScheme.primary),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(title, style: context.listTitleStyle),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.listSubtitleStyle,
              ),
            ],
          ),
        ),
        const GlyphIcon(AppGlyphs.chevronForward, size: 18),
      ],
    );
  }
}

class _RecentQueries extends ConsumerWidget {
  const _RecentQueries({required this.running});

  final bool running;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!running) return const SizedBox.shrink();
    final recent = ref.watch(
      serverQueryLogProvider(const ServerLogQuery(limit: 5)),
    );
    return ServerSectionCard(
      onPressed: () => context.go(ServerRoutes.logs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.serverRecentQueries,
                  style: context.listTitleStyle,
                ),
              ),
              const GlyphIcon(AppGlyphs.chevronForward, size: 18),
            ],
          ),
          recent.when(
            data: (result) => result.entries.isEmpty
                ? Text(
                    context.l10n.serverNoQueries,
                    style: context.listSubtitleStyle,
                  )
                : Column(
                    children: [
                      for (final record in result.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            spacing: 8,
                            children: [
                              Expanded(
                                child: Text(
                                  record.domain,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyle.footnote.of(context),
                                ),
                              ),
                              Text(
                                record.status,
                                style: AppTextStyle.caption2
                                    .of(context)
                                    .copyWith(
                                      color: record.blocked
                                          ? context.colorScheme.error
                                          : context
                                                .colorScheme
                                                .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
            loading: () => const Center(child: CommonCircleLoading(size: 18)),
            error: (error, _) =>
                Text(error.toString(), style: context.listSubtitleStyle),
          ),
        ],
      ),
    );
  }
}
