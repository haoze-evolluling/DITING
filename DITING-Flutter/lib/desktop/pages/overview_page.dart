import 'package:diting/desktop/data/desktop_models.dart';
import 'package:diting/desktop/state/desktop_providers.dart';
import 'package:diting/desktop/widgets/desktop_components.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(desktopDashboardProvider);
    final snapshot = state.snapshot;
    return DesktopPage(
      children: [
        if (state.error != null) ...[
          _ErrorBanner(message: state.error!),
          const SizedBox(height: 18),
        ],
        _HeroControl(snapshot: snapshot),
        const SizedBox(height: 20),
        _MetricsGrid(snapshot: snapshot),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final resolution = _ResolutionCard(snapshot: snapshot);
            final protection = _ProtectionCard(snapshot: snapshot);
            if (!wide) {
              return Column(
                children: [resolution, const SizedBox(height: 20), protection],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: resolution),
                const SizedBox(width: 20),
                Expanded(child: protection),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _HeroControl extends ConsumerWidget {
  const _HeroControl({required this.snapshot});

  final DesktopSnapshot? snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(desktopDashboardProvider);
    final running = snapshot?.dns.running ?? false;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: .72),
            scheme.surfaceContainerLow,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.primary.withValues(alpha: .12)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 650;
          final icon = Container(
            width: compact ? 54 : 68,
            height: compact ? 54 : 68,
            decoration: BoxDecoration(
              color: running ? scheme.primary : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              running ? Icons.shield_outlined : Icons.shield_moon_outlined,
              size: compact ? 28 : 34,
              color: running ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          );
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                snapshot == null
                    ? '正在等待本机服务'
                    : running
                    ? '网络保护已开启'
                    : '谛听已准备就绪',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 610),
                child: Text(
                  snapshot == null
                      ? '连接后将在这里展示 DNS 解析、缓存与防护的真实状态。'
                      : running
                      ? '域名解析正在本机完成，缓存加速与规则防护持续生效。'
                      : '开启 DNS 解析后，即可使用本地加速与网络防护能力。',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusPill(
                    label: running ? 'DNS 运行中' : 'DNS 已停止',
                    tone: running ? StatusTone.positive : StatusTone.neutral,
                  ),
                  if (snapshot?.takeover.active == true)
                    StatusPill(
                      label: '已保护 ${snapshot!.takeover.adapterCount} 个网卡',
                      tone: StatusTone.positive,
                    ),
                ],
              ),
            ],
          );
          final control = Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Transform.scale(
                scale: 1.15,
                child: Switch(
                  value: running,
                  onChanged: snapshot == null || state.isActionBusy
                      ? null
                      : (value) => _changeDns(context, ref, value),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                state.isActionBusy ? '正在应用' : '解析服务',
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [icon, const Spacer(), control]),
                const SizedBox(height: 22),
                copy,
              ],
            );
          }
          return Row(
            children: [
              icon,
              const SizedBox(width: 22),
              Expanded(child: copy),
              const SizedBox(width: 20),
              control,
            ],
          );
        },
      ),
    );
  }

  Future<void> _changeDns(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    try {
      await ref.read(desktopDashboardProvider.notifier).setDnsRunning(value);
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.snapshot});

  final DesktopSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final metrics = snapshot?.metrics;
    final tiles = [
      MetricTile(
        label: '实时查询速率',
        value: metrics?.qps.toStringAsFixed(1) ?? '—',
        unit: metrics == null ? null : '次/秒',
        icon: Icons.bolt_outlined,
      ),
      MetricTile(
        label: '平均响应耗时',
        value: metrics?.averageLatencyMs.toStringAsFixed(1) ?? '—',
        unit: metrics == null ? null : 'ms',
        icon: Icons.speed_outlined,
      ),
      MetricTile(
        label: '解析成功率',
        value: snapshot == null
            ? '—'
            : '${(snapshot!.successRate * 100).toStringAsFixed(1)}%',
        icon: Icons.task_alt_outlined,
      ),
      MetricTile(
        label: '持续运行时长',
        value: snapshot == null ? '—' : formatUptime(snapshot!.uptimeSeconds),
        icon: Icons.schedule_outlined,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 440
            ? 2
            : 1;
        const gap = 14.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}

class _ResolutionCard extends ConsumerWidget {
  const _ResolutionCard({required this.snapshot});

  final DesktopSnapshot? snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(desktopDashboardProvider);
    final takeover = snapshot?.takeover;
    final cache = snapshot?.cache;
    return DesktopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeading(
            title: '解析与网络接管',
            subtitle: snapshot == null
                ? '等待后台状态'
                : '${snapshot!.dns.modeLabel} · ${snapshot!.dns.upstreams.length} 个上游',
            icon: Icons.dns_outlined,
          ),
          const SizedBox(height: 22),
          _InfoRow(
            label: '监听地址',
            value: snapshot?.dns.primaryAddress ?? '—',
            monospace: true,
          ),
          const SizedBox(height: 12),
          _InfoRow(
            label: '缓存命中',
            value: cache == null
                ? '—'
                : '${(cache.hitRatio * 100).toStringAsFixed(1)}% · ${formatCount(cache.entryCount)} 条',
          ),
          const Divider(height: 30),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '物理网卡保护',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      takeover?.active == true
                          ? '已接管 ${takeover!.adapterCount} 个网卡'
                          : '当前未接管网卡',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Switch(
                value: takeover?.active ?? false,
                onChanged:
                    snapshot == null ||
                        state.isActionBusy ||
                        snapshot?.dns.running != true
                    ? null
                    : (value) => _changeTakeover(context, ref, value),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _changeTakeover(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    try {
      await ref.read(desktopDashboardProvider.notifier).setTakeover(value);
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }
}

class _ProtectionCard extends StatelessWidget {
  const _ProtectionCard({required this.snapshot});

  final DesktopSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final filter = snapshot?.filter;
    return DesktopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeading(
            title: '规则防护',
            subtitle: filter == null
                ? '等待防护统计'
                : filter.paused
                ? '规则拦截暂时暂停'
                : filter.enabled
                ? '本地规则引擎正在工作'
                : '规则拦截未开启',
            icon: Icons.verified_user_outlined,
            trailing: filter == null
                ? null
                : StatusPill(
                    label: filter.paused
                        ? '已暂停'
                        : filter.enabled
                        ? '防护中'
                        : '未开启',
                    tone: filter.enabled && !filter.paused
                        ? StatusTone.positive
                        : StatusTone.neutral,
                  ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _SmallStatistic(
                  label: '有效规则',
                  value: filter == null ? '—' : formatCount(filter.totalRules),
                ),
              ),
              Expanded(
                child: _SmallStatistic(
                  label: '启用订阅',
                  value: filter == null ? '—' : '${filter.activeLists}',
                ),
              ),
              Expanded(
                child: _SmallStatistic(
                  label: '累计拦截',
                  value: filter == null
                      ? '—'
                      : formatCount(filter.blockedQueries),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: filter == null ? 0 : (filter.blockRate / 100).clamp(0, 1),
              minHeight: 7,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            filter == null
                ? '连接后显示查询拦截比例'
                : '查询拦截比例 ${filter.blockRate.toStringAsFixed(1)}%',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      ),
      Flexible(
        child: Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontFamily: monospace ? 'monospace' : null,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

class _SmallStatistic extends StatelessWidget {
  const _SmallStatistic({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _ErrorBanner extends ConsumerWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          TextButton(
            onPressed: () =>
                ref.read(desktopDashboardProvider.notifier).refresh(),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(error.toString()),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
