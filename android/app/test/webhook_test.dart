// A11: webhook signing header + retry loop, exercised through a fake transport so no socket is
// opened. The signatures themselves come from the real native kernel.

import 'package:diting_android/data/webhook/rust_webhook_core.dart';
import 'package:diting_android/data/webhook/webhook_dispatcher.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTransport implements WebhookTransport {
  _FakeTransport(this.responses);

  /// Each entry is an `int` status or a `String` error to throw.
  final List<Object> responses;
  int calls = 0;
  final List<Map<String, String>> headers = [];

  @override
  Future<WebhookHttpResponse> post(
    Uri url,
    Map<String, String> headerMap,
    String body,
  ) async {
    headers.add(headerMap);
    final response = responses[calls++];
    if (response is int) return WebhookHttpResponse(response);
    throw response;
  }
}

void main() {
  const url = 'https://example.com/hook';
  const secret = 's3cr3t';
  const fixedSecond = 1700000000;

  WebhookDispatcher build(_FakeTransport transport, {List<Duration>? sleeps}) {
    return WebhookDispatcher(
      transport: transport,
      sleep: (duration) async => sleeps?.add(duration),
      maxAttempts: 3,
      baseDelayMs: 1000,
      maxDelayMs: 30000,
      clockSeconds: () => fixedSecond,
    );
  }

  test('首次成功：签名头与内核一致，只发一次', () async {
    final transport = _FakeTransport([200]);
    final result = await build(transport).deliver(
      url: url,
      secret: secret,
      payload: const {'event': 'test'},
    );

    expect(result.ok, isTrue);
    expect(result.attempts, 1);
    expect(transport.calls, 1);
    final body = '{"event":"test"}';
    final expected = RustWebhookCore.instance.sign(
      secret: secret,
      body: body,
      timestamp: fixedSecond,
    );
    expect(transport.headers.single['X-Diting-Signature'], expected);
    expect(transport.headers.single['X-Diting-Timestamp'], '$fixedSecond');
  });

  test('5xx 重试后成功：共 3 次并按退避等待', () async {
    final sleeps = <Duration>[];
    final transport = _FakeTransport([500, 503, 200]);
    final result = await build(transport, sleeps: sleeps).deliver(
      url: url,
      secret: secret,
      payload: const {'event': 'x'},
    );

    expect(result.ok, isTrue);
    expect(result.attempts, 3);
    expect(sleeps, [const Duration(milliseconds: 1000), const Duration(milliseconds: 2000)]);
  });

  test('4xx 不重试', () async {
    final transport = _FakeTransport([404]);
    final result = await build(transport).deliver(
      url: url,
      secret: secret,
      payload: const {'event': 'x'},
    );

    expect(result.ok, isFalse);
    expect(result.status, 404);
    expect(transport.calls, 1);
  });

  test('网络异常按可重试处理，用尽后失败', () async {
    final sleeps = <Duration>[];
    final transport = _FakeTransport(['boom', 'boom', 'boom']);
    final result = await build(transport, sleeps: sleeps).deliver(
      url: url,
      secret: secret,
      payload: const {'event': 'x'},
    );

    expect(result.ok, isFalse);
    expect(transport.calls, 3);
    expect(sleeps, hasLength(2));
  });

  test('非法地址直接失败，不发起请求', () async {
    final transport = _FakeTransport([]);
    final result = await build(transport).deliver(
      url: 'not a url',
      secret: secret,
      payload: const {'event': 'x'},
    );

    expect(result.ok, isFalse);
    expect(transport.calls, 0);
  });
}
