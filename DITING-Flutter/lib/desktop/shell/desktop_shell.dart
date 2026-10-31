import 'package:diting/desktop/app/desktop_router.dart';
import 'package:diting/desktop/state/desktop_providers.dart';
import 'package:diting/desktop/widgets/desktop_components.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DesktopShell extends ConsumerWidget {
  const DesktopShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = GoRouterState.of(context).uri.path;
    final section = DesktopSection.fromPath(path);
    final state = ref.watch(desktopDashboardProvider);
    final scheme = Theme.of(context).colorScheme;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f5): () =>
            ref.read(desktopDashboardProvider.notifier).refresh(),
        for (var index = 0; index < DesktopSection.values.length; index++)
          SingleActivator(_numberKeys[index], control: true): () =>
              context.go(DesktopSection.values[index].path),
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            final expanded = constraints.maxWidth >= 1120;
            final navigation = compact
                ? null
                : _SideNavigation(
                    section: section,
                    expanded: expanded,
                    connected: state.snapshot != null,
                  );
            return Scaffold(
              body: Row(
                children: [
                  ?navigation,
                  Expanded(
                    child: ColoredBox(
                      color: scheme.surface,
                      child: Column(
                        children: [
                          _TopBar(section: section, compact: compact),
                          Expanded(
                            child: KeyedSubtree(
                              key: ValueKey(section),
                              child: child,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: compact
                  ? NavigationBar(
                      height: 68,
                      selectedIndex: section.index,
                      onDestinationSelected: (index) =>
                          context.go(DesktopSection.values[index].path),
                      destinations: [
                        for (final item in DesktopSection.values)
                          NavigationDestination(
                            icon: Icon(item.icon, size: 22),
                            label: item.label,
                          ),
                      ],
                    )
                  : null,
            );
          },
        ),
      ),
    );
  }
}

const _numberKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
];

class _SideNavigation extends StatelessWidget {
  const _SideNavigation({
    required this.section,
    required this.expanded,
    required this.connected,
  });

  final DesktopSection section;
  final bool expanded;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: expanded ? 240 : 80,
      color: scheme.surfaceContainerLow,
      padding: EdgeInsets.symmetric(
        horizontal: expanded ? 16 : 10,
        vertical: 20,
      ),
      child: Column(
        children: [
          _Brand(expanded: expanded, connected: connected),
          const SizedBox(height: 30),
          for (final item in DesktopSection.values) ...[
            _NavigationItem(
              section: item,
              selected: item == section,
              expanded: expanded,
            ),
            const SizedBox(height: 6),
          ],
          const Spacer(),
          if (expanded)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.keyboard_outlined,
                    size: 17,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ctrl + 1–5 快速切换\nF5 刷新状态',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.expanded, required this.connected});

  final bool expanded;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final logo = Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            'assets/images/icon.png',
            width: 40,
            height: 40,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected ? scheme.tertiary : scheme.outline,
              border: Border.all(color: scheme.surfaceContainerLow, width: 2),
            ),
          ),
        ),
      ],
    );
    return InkWell(
      onTap: () => context.go(DesktopSection.overview.path),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: expanded
            ? Row(
                children: [
                  logo,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '谛听',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'DITING DNS',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: scheme.onSurfaceVariant,
                                letterSpacing: 1.1,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Tooltip(message: '谛听 DNS · 返回总览', child: logo),
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.section,
    required this.selected,
    required this.expanded,
  });

  final DesktopSection section;
  final bool selected;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;
    final item = Material(
      color: selected ? scheme.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => context.go(section.path),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 48,
          padding: EdgeInsets.symmetric(horizontal: expanded ? 14 : 0),
          alignment: expanded ? Alignment.centerLeft : Alignment.center,
          child: expanded
              ? Row(
                  children: [
                    Icon(section.icon, size: 22, color: foreground),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Text(
                        section.label,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: foreground,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (selected)
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: foreground,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                )
              : Icon(section.icon, size: 23, color: foreground),
        ),
      ),
    );
    return expanded ? item : Tooltip(message: section.label, child: item);
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.section, required this.compact});

  final DesktopSection section;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(desktopDashboardProvider);
    final snapshot = state.snapshot;
    final status = snapshot == null
        ? (state.isRefreshing ? '正在连接' : '服务未连接')
        : snapshot.dns.running
        ? '保护运行中'
        : '解析已停止';
    final tone = snapshot == null
        ? StatusTone.neutral
        : snapshot.dns.running
        ? StatusTone.positive
        : StatusTone.warning;
    return Container(
      height: 76,
      padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 28),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant
                .withValues(alpha: .4),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.label,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (!compact)
                  Text(
                    section.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (!compact) ...[
            StatusPill(label: status, tone: tone),
            const SizedBox(width: 8),
          ],
          IconButton(
            onPressed: state.isRefreshing
                ? null
                : () => ref.read(desktopDashboardProvider.notifier).refresh(),
            tooltip: '刷新状态 (F5)',
            icon: state.isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
    );
  }
}
