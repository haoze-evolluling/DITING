import 'dart:async';

import 'package:diting_android/data/server/server_runtime_models.dart';
import 'package:diting_android/pages/home/widgets/home_power_button.dart';
import 'package:diting_android/pages/server/server_common.dart';
import 'package:diting_android/pages/server/server_home_insights.dart';
import 'package:diting_android/pages/server/server_home_rankings.dart';
import 'package:diting_android/pages/server/server_home_request_overview.dart';
import 'package:diting_android/pages/server/server_home_status.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/routes/branches.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/stat_strip.dart';
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
            if (_busy) return;
            final running =
                ref.read(serverControllerProvider).value?.status.running ??
                false;
            if (running) {
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
    if (_busy || status.isBusy) return;
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
      title: context.l10n.homeTitleServer,
      actions: [
        IconButton(
          tooltip: context.l10n.homeSwitchWorkMode,
          onPressed: () => context.push(Routes.modeSelect),
          icon: const Icon(TablerIcons.arrows_exchange),
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
              busyLabel: value.status.stopping
                  ? context.l10n.stateStopping
                  : context.l10n.serverStarting,
            ),
            ServerStatusOverview(status: value.status, config: value.config),
            ServerQuickActions(config: value.config),
            ServerRequestOverview(stats: value.stats),
            ServerTrafficOverview(
              stats: value.stats,
              running: value.status.running,
            ),
            ServerBlockingOverview(stats: value.stats),
            ServerCacheOverview(stats: value.stats),
            ServerTopDomainsOverview(stats: value.stats),
            ServerTopClientsOverview(stats: value.stats),
            ServerRecentQueries(running: value.status.running),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

bool _canFallbackTo1053(ServerStatus status) =>
    status.root && status.error?.contains('53') == true;
