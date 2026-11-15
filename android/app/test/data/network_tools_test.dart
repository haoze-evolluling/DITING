// Network tools against real HTTP replies: WebDAV and the IP quality checker,
// where every branch is decided by an actual response.

import 'dart:convert';
import 'dart:io';

import 'package:diting_android/data/backup/dav_client.dart';
import 'package:diting_android/data/tools/ip_quality_checker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WebDAV 客户端', _davClient);
  group('IP 质量检测', _ipQuality);
}

void _davClient() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // `flutter_test` installs `HttpOverrides.global` answering 400; this file uses a loopback server
  setUpAll(() => HttpOverrides.global = null);

  late HttpServer server;
  late String baseUrl;

  const goodAuth = 'diting:secret';

  late List<({String method, String path, bool authorized})> requests;

  late Set<String> existingDirs;

  late Map<String, String> files;

  setUp(() async {
    requests = [];
    existingDirs = {};
    files = {};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';

    server.listen((request) async {
      final auth = request.headers.value(HttpHeaders.authorizationHeader);
      final expected = 'Basic ${base64Encode(utf8.encode(goodAuth))}';
      final authorized = auth == expected;
      requests.add((
        method: request.method,
        path: request.uri.path,
        authorized: authorized,
      ));
      // Drain the body before responding, or the unread body keeps the socket open forever
      final body = await utf8.decoder.bind(request).join();
      if (!authorized) {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.headers.set(
          HttpHeaders.wwwAuthenticateHeader,
          'Basic realm="test"',
        );
        await request.response.close();
        return;
      }
      final path = request.uri.path;
      switch (request.method) {
        case 'PROPFIND':
          if (existingDirs.contains(path)) {
            request.response.statusCode = 207;
            request.response.write(
              '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:"/>',
            );
          } else {
            request.response.statusCode = HttpStatus.notFound;
          }
        case 'MKCOL':
          existingDirs.add(path);
          request.response.statusCode = HttpStatus.created;
        case 'PUT':
          files[path] = body;
          request.response.statusCode = HttpStatus.ok;
        case 'GET':
          final stored = files[path];
          if (stored == null) {
            request.response.statusCode = HttpStatus.notFound;
          } else {
            request.response.statusCode = HttpStatus.ok;
            request.response.write(stored);
          }
        default:
          request.response.statusCode = HttpStatus.methodNotAllowed;
      }
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  DavCredentials credentials({String password = 'secret', String? path}) =>
      DavCredentials(
        server: baseUrl,
        username: 'diting',
        password: password,
        path: path ?? '/diting/',
      );

  group('probe', () {
    test('目录已存在时报告未创建，且真的发了 PROPFIND', () async {
      existingDirs.add('/diting/');
      final result = await const DavClient().probe(credentials());

      expect(result.succeeded, isTrue);
      expect(result.created, isFalse);
      expect(requests.single.method, 'PROPFIND');
      expect(requests.single.authorized, isTrue);
    });

    test('目录不存在时自动 MKCOL 并报告已创建', () async {
      final result = await const DavClient().probe(credentials());

      expect(result.succeeded, isTrue);
      expect(result.created, isTrue);
      expect(requests.map((item) => item.method), ['PROPFIND', 'MKCOL']);
      expect(existingDirs, contains('/diting/'));
    });

    test('密码错误时报 401 而不是「连接成功」', () async {
      final result = await const DavClient().probe(
        credentials(password: 'wrong'),
      );

      expect(result.succeeded, isFalse);
      expect(result.statusCode, 401);
      expect(result.error, contains('认证失败'));
    });

    test('服务器不可达时报告无法连接', () async {
      // Nothing listens on port 1: the shape of a nonexistent address.
      final result = await const DavClient().probe(
        const DavCredentials(
          server: 'http://127.0.0.1:1',
          username: 'diting',
          password: 'secret',
          path: '/diting/',
        ),
      );
      expect(result.succeeded, isFalse);
      expect(result.error, contains('无法连接'));
    });

    test('远端路径缺前导/尾部斜杠会被补齐', () async {
      existingDirs.add('/dav/sub/');
      final result = await const DavClient().probe(
        credentials(path: 'dav/sub'),
      );

      expect(result.succeeded, isTrue);
      expect(requests.single.path, '/dav/sub/');
    });
  });

  group('上传与下载', () {
    test('PUT 写入真实内容，GET 取回同一份', () async {
      final client = const DavClient();
      final payload = '{"format":"diting-backup","version":1}';

      final uploaded = await client.putText(
        credentials(),
        name: 'diting-config.json',
        content: payload,
      );
      expect(uploaded.succeeded, isTrue);
      expect(files['/diting/diting-config.json'], payload);

      final downloaded = await client.getText(
        credentials(),
        name: 'diting-config.json',
      );
      expect(downloaded, payload);
    });

    test('云端文件不存在时返回 null 而不是抛错', () async {
      final result = await const DavClient().getText(
        credentials(),
        name: 'missing.json',
      );
      expect(result, isNull);
    });
  });

  group('凭据', () {
    test('目录地址拼接带尾部斜杠，文件名在其下', () {
      final normalized = credentials(path: '/a/b').normalized();
      expect(normalized.directoryUrl, '$baseUrl/a/b/');
      expect(normalized.fileUrl('x.json'), '$baseUrl/a/b/x.json');
    });
  });
}

/// Pins the checker against real HTTP replies, including the partial and empty cases

void _ipQuality() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => HttpOverrides.global = null);

  late HttpServer server;
  late String base;
  late Map<String, String> routes;
  late Map<String, int> statuses;

  setUp(() async {
    routes = {};
    statuses = {};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      final path = request.uri.path;
      String? key;
      for (final candidate in routes.keys) {
        if (path == candidate || path.startsWith('$candidate/')) {
          key = candidate;
          break;
        }
      }
      final body = key == null ? null : routes[key];
      request.response.statusCode =
          (key == null ? null : statuses[key]) ?? (body == null ? 404 : 200);
      request.response.write(body ?? 'not found');
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  IpQualityChecker checker() => IpQualityChecker(
    probeUrls: ['$base/ip'],
    ipApiUrl: '$base/ip-api',
    ipWhoIsUrl: '$base/ipwho',
    ipInfoUrl: '$base/ipinfo',
  );

  void stubAll({
    String ip = '1.2.3.4',
    String ipApi =
        '{"status":"success","as":"AS15169 Google LLC","isp":"Google"}',
    String ipWho =
        '{"success":true,"connection":{"asn":15169,"isp":"Google LLC"}}',
    String ipInfo = '{"org":"AS15169 Google LLC"}',
  }) {
    routes['/ip'] = jsonEncode({'ip': ip});
    routes['/ip-api'] = ipApi;
    routes['/ipwho'] = ipWho;
    routes['/ipinfo'] = ipInfo;
  }

  group('出口 IP', () {
    test('先取出口 IP，再拿它去查各源', () async {
      stubAll(ip: '9.9.9.9');
      final outcome = await checker().detect();
      expect(outcome, isA<IpQualitySuccess>());
      expect((outcome as IpQualitySuccess).report.ip, '9.9.9.9');
    });

    test('探测端点不可用时报失败，而不是回落到某个固定 IP', () async {
      routes['/ip'] = 'nope';
      statuses['/ip'] = 500;
      final outcome = await checker().detect();
      expect(outcome, isA<IpQualityError>());
      expect(
        (outcome as IpQualityError).failure.message,
        contains('无法获取当前出口 IP'),
      );
    });

    test('第一个探测端点不通时用下一个，而不是整次检测失败', () async {
      // `api.ipify.org` was reset while `api64.ipify.org` answered 200: one endpoint would report
      // down
      stubAll(ip: '9.9.9.9');
      statuses['/ip'] = 500;
      routes['/ip2'] = jsonEncode({'ip': '8.8.8.8'});
      final outcome = await IpQualityChecker(
        probeUrls: ['$base/ip', '$base/ip2'],
        ipApiUrl: '$base/ip-api',
        ipWhoIsUrl: '$base/ipwho',
        ipInfoUrl: '$base/ipinfo',
      ).detect();
      expect(outcome, isA<IpQualitySuccess>());
      expect((outcome as IpQualitySuccess).report.ip, '8.8.8.8');
    });
  });

  group('多源汇总', () {
    test('全部命中时类型与级别来自真实数据', () async {
      stubAll();
      final outcome = await checker().detect() as IpQualitySuccess;
      final report = outcome.report;
      expect(report.ipType, '机房');
      expect(report.level, '风险');
      expect(report.asn, 'AS15169');
      expect(report.organization, 'Google');
      expect(report.hitCount, 3);
    });

    test('一个源失败不影响其余源出结论', () async {
      stubAll();
      statuses['/ip-api'] = 429;
      final report = (await checker().detect() as IpQualitySuccess).report;
      final ipApi = report.sources.firstWhere((s) => s.name == 'ip-api.com');
      expect(ipApi.status, '限流');
      expect(report.hitCount, 2);
      expect(report.level, '风险');
    });

    test('全部源失败时明确报错，而不是编一份「优秀」', () async {
      routes['/ip'] = jsonEncode({'ip': '1.2.3.4'});
      for (final path in ['/ip-api', '/ipwho', '/ipinfo']) {
        routes[path] = '{"status":"fail"}';
        statuses[path] = 500;
      }
      final outcome = await checker().detect();
      expect(outcome, isA<IpQualityError>());
      expect((outcome as IpQualityError).failure.message, contains('均未返回结果'));
    });

    test('ipinfo 额度用尽被标为限流而不是失败', () async {
      stubAll(ipInfo: '{"error":{"message":"rate limited"}}');
      final report = (await checker().detect() as IpQualitySuccess).report;
      final info = report.sources.firstWhere((s) => s.name == 'ipinfo.io');
      expect(info.status, '限流');
    });
  });

  group('分类规则', () {
    Future<String> typeFor(String isp) async {
      stubAll(
        ipApi: jsonEncode({'status': 'success', 'as': 'AS1 $isp', 'isp': isp}),
        ipWho: jsonEncode({
          'success': true,
          'connection': {'asn': 1, 'isp': isp},
        }),
        ipInfo: jsonEncode({'org': 'AS1 $isp'}),
      );
      return (await checker().detect() as IpQualitySuccess).report.ipType;
    }

    test('云厂商关键词判为机房', () async {
      expect(await typeFor('Amazon.com Inc.'), '机房');
      expect(await typeFor('Cloudflare Inc'), '机房');
      expect(await typeFor('DigitalOcean LLC'), '机房');
    });

    test('移动运营商判为移动', () async {
      expect(await typeFor('China Mobile'), '移动');
      expect(await typeFor('T-Mobile USA'), '移动');
    });

    test('未知组织兜底为商业，不默认成住宅', () async {
      expect(await typeFor('Some Random ISP'), '商业');
    });
  });
}

/// Network-tool judging rules: host sanitizing, a sparse `fromMap`, and every panel state
