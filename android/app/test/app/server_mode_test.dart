import 'dart:async';

import 'package:diting_android/data/server/server_launch_models.dart';
import 'package:diting_android/data/server/server_runtime_models.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_server_client.dart';

class _AsyncTransitionServerClient extends FakeServerClient {
  _AsyncTransitionServerClient({
    required this.startDelay,
    required this.stopDelay,
  });

  final Duration startDelay;
  final Duration stopDelay;

  @override
  Future<bool> start({required bool preferRoot}) async {
    emitStatus(
      ServerStatus(
        starting: true,
        root: preferRoot,
        port: preferRoot ? 53 : 1053,
      ),
    );
    unawaited(
      Future<void>.delayed(startDelay, () {
        emitStatus(
          ServerStatus(
            running: true,
            root: preferRoot,
            port: preferRoot ? 53 : 1053,
            addresses: [preferRoot ? '0.0.0.0:53' : '0.0.0.0:1053'],
          ),
        );
      }),
    );
    return true;
  }

  @override
  Future<bool> stop() async {
    emitStatus(const ServerStatus(stopping: true));
    unawaited(
      Future<void>.delayed(stopDelay, () {
        emitStatus(const ServerStatus());
      }),
    );
    return true;
  }
}

void main() {
  test('server controller follows start and stop state', () async {
    final client = FakeServerClient();
    final container = ProviderContainer(
      overrides: [serverClientProvider.overrideWithValue(client)],
    );
    addTearDown(() {
      container.dispose();
      client.dispose();
    });

    final initial = await container.read(serverControllerProvider.future);
    expect(initial.status.running, isFalse);
    expect(
      await container.read(
        serverQueryLogProvider(const ServerLogQuery()).future,
      ),
      isA<ServerQueryResult>().having((result) => result.total, 'total', 0),
    );

    await container
        .read(serverControllerProvider.notifier)
        .start(preferRoot: false);
    final running = container.read(serverControllerProvider).value!;
    expect(running.status.running, isTrue);
    expect(running.status.port, 1053);

    await container.read(serverControllerProvider.notifier).stop();
    final stopped = container.read(serverControllerProvider).value!;
    expect(stopped.status.running, isFalse);
  });

  test('start and stop settle immediately from status stream events', () async {
    final client = _AsyncTransitionServerClient(
      startDelay: const Duration(milliseconds: 30),
      stopDelay: const Duration(milliseconds: 30),
    );
    final container = ProviderContainer(
      overrides: [serverClientProvider.overrideWithValue(client)],
    );
    addTearDown(() {
      container.dispose();
      client.dispose();
    });

    await container.read(serverControllerProvider.future);

    final startWatch = Stopwatch()..start();
    await container
        .read(serverControllerProvider.notifier)
        .start(preferRoot: false);
    startWatch.stop();

    final running = container.read(serverControllerProvider).value!;
    expect(running.status.running, isTrue);
    expect(running.status.starting, isFalse);
    expect(startWatch.elapsedMilliseconds, lessThan(500));

    final stopFuture = container.read(serverControllerProvider.notifier).stop();
    expect(
      container.read(serverControllerProvider).value!.status.stopping,
      isTrue,
    );
    final stopWatch = Stopwatch()..start();
    await stopFuture;
    stopWatch.stop();

    final stopped = container.read(serverControllerProvider).value!;
    expect(stopped.status.running, isFalse);
    expect(stopped.status.stopping, isFalse);
    expect(stopWatch.elapsedMilliseconds, lessThan(500));
  });

  test('restarting status stays active and keeps the last error', () {
    final status = ServerStatus.fromMap({
      'restarting': true,
      'port': 1053,
      'pid': 0,
      'error': 'process exited with code 1',
    });

    expect(status.restarting, isTrue);
    expect(status.running, isFalse);
    expect(status.isBusy, isFalse);
    expect(status.active, isTrue);
    expect(status.error, 'process exited with code 1');
  });

  test('launch settings default to keep-alive on', () {
    const settings = ServerLaunchSettings();
    expect(settings.autoStart, isFalse);
    expect(settings.autoRestart, isTrue);
  });
}
