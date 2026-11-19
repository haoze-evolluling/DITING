import 'package:diting_android/data/server/server_runtime_models.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_server_client.dart';

void main() {
  test('server controller follows start and stop state', () async {
    final client = FakeServerClient();
    final container = ProviderContainer(
      overrides: [serverClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

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

  test('log query values are stable Riverpod family keys', () {
    const first = ServerLogQuery(domain: 'a.example', status: 'blocked');
    const second = ServerLogQuery(domain: 'a.example', status: 'blocked');
    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });
}
