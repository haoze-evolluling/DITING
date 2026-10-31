import 'dart:convert';

import 'package:diting/desktop/data/desktop_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('HTTP 适配层解包现有 Go API 响应并调用正确控制端点', () async {
    final requests = <http.Request>[];
    final backend = HttpDesktopBackend(
      token: 'secret',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/v1/status') {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'version': '1.4.3',
                'dns': {'running': true},
                'takeover': {},
                'metrics': {},
              },
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'success': true}), 200);
      }),
    );

    final snapshot = await backend.getSnapshot();
    await backend.setDnsRunning(false);
    await backend.setTakeover(true);

    expect(snapshot.version, '1.4.3');
    expect(snapshot.dns.running, isTrue);
    expect(requests.map((request) => request.method), ['GET', 'POST', 'POST']);
    expect(requests[1].url.path, '/api/v1/dns/stop');
    expect(requests[2].url.path, '/api/v1/takeover/enable');
    expect(requests.first.headers['Authorization'], 'Bearer secret');
    expect(requests.first.headers['X-API-Token'], 'secret');
  });

  test('HTTP 适配层透传后端可读错误', () async {
    final backend = HttpDesktopBackend(
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(jsonEncode({'success': false, 'error': '53 端口被占用'})),
          409,
        ),
      ),
    );

    expect(
      backend.setDnsRunning(true),
      throwsA(
        isA<DesktopBackendException>().having(
          (error) => error.message,
          'message',
          '53 端口被占用',
        ),
      ),
    );
  });
}
