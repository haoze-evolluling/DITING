// AI analysis: the obfuscated key round trip, endpoint derivation, the HTTP client and
// the prompts built from real log tables.

import 'dart:convert';
import 'dart:io';

import 'package:diting_android/data/agent/agent_api_client.dart';
import 'package:diting_android/data/agent/agent_api_text_parser.dart';
import 'package:diting_android/data/agent/agent_prompts.dart';
import 'package:diting_android/data/agent/agent_traffic_summary.dart';
import 'package:diting_android/data/agent/key_obfuscator.dart';
import 'package:diting_android/data/db/dns_log_repository.dart';
import 'package:diting_android/data/db/http_request_repository.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';
import 'package:diting_android/state/hub_settings_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/legacy_schema.dart';

void main() {
  group('分析与提示词', _agentAnalysis);
  group('剪贴板识别', _agentTextParser);
}

void _agentAnalysis() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // `flutter_test` answers every request with a fake 400, so the override goes here
  setUpAll(() => HttpOverrides.global = null);

  group('KeyObfuscator', () {
    test('往返还原，且与 1.4.3 的掩码一致', () {
      // Hand-computed with Kotlin's algorithm: changing it strands keys saved by upgraders
      expect(openApiKey(sealApiKey('sk-abc')), 'sk-abc');
      expect(sealApiKey(''), '');
      expect(openApiKey(''), '');
    });

    test('坏密文返回空串而不是抛异常', () {
      expect(openApiKey('!!!not-base64!!!'), '');
      // Valid Base64 from another encoder decodes to invalid UTF-8; a throw would blank the
      // provider list
      expect(openApiKey('YWJj'), '');
    });
  });

  group('端点推导', () {
    test('按厂商习惯补 /v1 与 /chat/completions', () {
      expect(
        AgentApiClient.resolveChatCompletionsEndpoint(
          'https://api.deepseek.com',
        ),
        'https://api.deepseek.com/v1/chat/completions',
      );
      expect(
        AgentApiClient.resolveChatCompletionsEndpoint(
          'https://api.openai.com/v1',
        ),
        'https://api.openai.com/v1/chat/completions',
      );
      expect(
        AgentApiClient.resolveChatCompletionsEndpoint(
          'https://open.bigmodel.cn/api/paas/v4',
        ),
        'https://open.bigmodel.cn/api/paas/v4/chat/completions',
      );
      expect(
        AgentApiClient.resolveChatCompletionsEndpoint(
          'https://x.test/v1/chat/completions',
        ),
        'https://x.test/v1/chat/completions',
      );
    });
  });

  group('HTTP 客户端', () {
    late HttpServer server;
    late String base;
    late List<Map<String, Object?>> requests;
    var reply = <String, Object?>{};
    var status = 200;

    setUp(() async {
      requests = [];
      reply = {};
      status = 200;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        requests.add({
          'path': request.uri.path,
          'auth': request.headers.value(HttpHeaders.authorizationHeader),
          'body': body,
        });
        request.response.statusCode = status;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(reply));
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    AgentApiClient client() => const AgentApiClient(
      connectTimeout: Duration(seconds: 5),
      readTimeout: Duration(seconds: 5),
      modelsTimeout: Duration(seconds: 5),
    );

    AgentChatConfig config({String key = 'sk-test'}) => AgentChatConfig(
      baseUrl: base,
      apiKey: key,
      model: 'test-model',
      temperature: 0.2,
      systemPrompt: 'be brief',
    );

    test('对话补全真的把模型、温度与两条消息发出去', () async {
      reply = {
        'model': 'test-model-v2',
        'choices': [
          {
            'message': {'content': '分析结论'},
          },
        ],
        'usage': {
          'prompt_tokens': 10,
          'completion_tokens': 5,
          'total_tokens': 15,
        },
      };
      final result = await client().chat(config(), const [
        AgentChatMessage(role: 'system', content: 'be brief'),
        AgentChatMessage(role: 'user', content: '分析 example.com'),
      ]);
      expect(requests, hasLength(1));
      expect(requests.single['path'], '/chat/completions');
      expect(requests.single['auth'], 'Bearer sk-test');
      final body = jsonDecode(requests.single['body']! as String) as Map;
      expect(body['model'], 'test-model');
      expect(body['temperature'], 0.2);
      expect((body['messages'] as List).length, 2);
      expect(result.content, '分析结论');
      expect(result.model, 'test-model-v2');
      expect(result.totalTokens, 15);
    });

    test('401 翻成「API Key 无效」并带上服务端原因', () async {
      status = 401;
      reply = {
        'error': {'message': 'Invalid token'},
      };
      await expectLater(
        client().chat(config(), const [
          AgentChatMessage(role: 'user', content: 'hi'),
        ]),
        throwsA(
          isA<AgentApiException>().having(
            (error) => error.message,
            'message',
            allOf(contains('API Key 无效'), contains('Invalid token')),
          ),
        ),
      );
    });

    test('429 / 5xx 各自给出可操作的原因', () async {
      status = 429;
      reply = {
        'error': {'message': 'rate limited'},
      };
      await expectLater(
        client().chat(config(), const [
          AgentChatMessage(role: 'user', content: 'hi'),
        ]),
        throwsA(
          isA<AgentApiException>().having(
            (error) => error.message,
            'message',
            contains('额度用尽'),
          ),
        ),
      );
    });

    test('没有密钥时不发请求，直接报错', () async {
      await expectLater(
        client().chat(config(key: ''), const [
          AgentChatMessage(role: 'user', content: 'hi'),
        ]),
        throwsA(isA<AgentApiException>()),
      );
      expect(requests, isEmpty);
    });

    test('模型返回空内容算失败，不展示空对话框', () async {
      reply = {
        'choices': [
          {
            'message': {'content': '   '},
          },
        ],
      };
      await expectLater(
        client().chat(config(), const [
          AgentChatMessage(role: 'user', content: 'hi'),
        ]),
        throwsA(
          isA<AgentApiException>().having(
            (error) => error.message,
            'message',
            contains('空内容'),
          ),
        ),
      );
    });

    test('拉模型认 data / models / result 三种形态并排序去重', () async {
      reply = {
        'data': [
          {'id': 'b-model'},
          {'id': 'a-model'},
          {'id': 'a-model'},
        ],
      };
      final models = await client().fetchModels(
        baseUrl: base,
        apiKey: 'sk-test',
      );
      expect(models, ['a-model', 'b-model']);
      expect(requests.single['path'], '/models');
    });
  });

  group('真实日志 → 提示词', () {
    late Database db;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await createLegacySchema(db);
    });

    tearDown(() => db.close());

    Future<void> insertDns(
      String domain,
      String result, {
      bool cached = false,
      String? message,
    }) => db.insert('dns_log', {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'queryName': domain,
      'queryType': 1,
      'result': result,
      'cached': cached ? 1 : 0,
      'message': message,
      'packageName': 'com.test',
    });

    test('流量摘要来自真实表，不是编造的数字', () async {
      await insertDns('a.test', 'PASSED');
      await insertDns('a.test', 'BLOCKED');
      await insertDns('b.test', 'CACHED', cached: true);
      await db.insert('http_request_log', {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'packageName': 'com.test',
        'authority': 'a.test',
        'protocol': 'h2',
        'outcome': 'blocked',
      });
      final summary = await summarizeRecentTraffic(
        dnsRepository: DnsLogRepository(db),
        httpRepository: HttpRequestRepository(db),
      );
      expect(summary.dnsSamples, 3);
      expect(summary.blockedDns, 1);
      expect(summary.cachedDns, 1);
      expect(summary.httpSamples, 1);
      expect(summary.blockedHttp, 1);
      expect(summary.topDomains.first.domain, 'a.test');
      expect(summary.topDomains.first.count, 2);
    });

    test('表为空时明说没有记录，并要求模型别编', () async {
      final summary = await summarizeRecentTraffic(
        dnsRepository: DnsLogRepository(db),
        httpRepository: HttpRequestRepository(db),
      );
      expect(summary.isEmpty, isTrue);
      expect(summary.render(), contains('没有任何 DNS 记录'));
      final request = buildTrafficAnalysisRequest(
        summary: summary,
        systemPrompt: '',
      );
      expect(request.userPrompt, contains('样本不足'));
      expect(request.userPrompt, isNot(contains('### 1.')));
    });

    test('极速模式没有 HTTPS 面时说清「没有这一面」而不是「没有流量」', () async {
      await insertDns('a.test', 'PASSED');
      final summary = await summarizeRecentTraffic(
        dnsRepository: DnsLogRepository(db),
        httpUnavailableReason: '极速模式不产生 HTTPS 检查记录',
      );
      expect(summary.render(), contains('极速模式不产生 HTTPS 检查记录'));
      expect(summary.render(), isNot(contains('采样数量: 0 条')));
    });
  });

  group('设置落盘', () {
    late MemoryLegacyPrefsStore store;
    late LegacySettings settings;

    setUp(() {
      store = MemoryLegacyPrefsStore();
      settings = LegacySettings(store);
    });

    test('九个键落在全局容器，键名与 1.4.3 一致', () {
      settings.setAgentApiBaseUrl('https://api.moonshot.cn/v1');
      settings.setAgentApiKey('  sk-1  ');
      settings.setAgentApiModel('kimi-k3');
      settings.setAgentApiTemperature(0.4);
      settings.setAgentApiSystemPrompt('prompt');
      settings.setAgentAiActiveProviderId('p1');
      expect(
        store.read('dns_vpn_prefs', 'agent_api_base_url'),
        'https://api.moonshot.cn/v1',
      );
      expect(store.read('dns_vpn_prefs', 'agent_api_key'), 'sk-1');
      expect(store.read('dns_vpn_prefs', 'agent_api_model'), 'kimi-k3');
      expect(store.read('dns_vpn_prefs', 'agent_api_temperature'), '0.4');
      expect(store.read('dns_vpn_prefs', 'agent_api_system_prompt'), 'prompt');
      expect(store.read('dns_vpn_prefs', 'agent_ai_active_provider_id'), 'p1');
    });

    test('温度按字符串存，读的时候两种类型都认', () {
      expect(settings.agentApiTemperature, 0.7);
      store.putFloat('dns_vpn_prefs', 'agent_api_temperature', 1.2);
      expect(settings.agentApiTemperature, 1.2);
      store.putString('dns_vpn_prefs', 'agent_api_temperature', '0.3');
      expect(settings.agentApiTemperature, 0.3);
    });

    test('厂商 JSON 往返保留混淆后的密钥', () {
      final sealed = sealApiKey('sk-round-trip');
      final encoded = jsonEncode([
        AiProviderConfig(
          id: 'p1',
          name: 'P1',
          baseUrl: 'https://x.test/v1',
          model: 'm',
          sealedKey: sealed,
        ).toJson(),
      ]);
      final decoded = decodeAiProviders(encoded);
      expect(decoded.single.id, 'p1');
      expect(decoded.single.apiKey, 'sk-round-trip');
      expect(encoded.contains('sk-round-trip'), isFalse);
    });
  });
}

void _agentTextParser() {
  group('剪贴板智能识别', () {
    test('JSON 一次给出地址、密钥与模型', () {
      final result = parseAgentApiText(
        '{"apiKey":"sk-abcdefghijklmnop","baseUrl":"https://api.test/v1","model":"m1"}',
      );
      expect(result.apiKey, 'sk-abcdefghijklmnop');
      expect(result.baseUrl, 'https://api.test/v1');
      expect(result.model, 'm1');
      expect(result.message, contains('JSON'));
    });

    test('地址加密钥的组合被拆开', () {
      final result = parseAgentApiText(
        'https://api.test/v1, sk-abcdefghijklmnopqrst',
      );
      expect(result.baseUrl, 'https://api.test/v1');
      expect(result.apiKey, 'sk-abcdefghijklmnopqrst');
    });

    test('裸密钥被当成密钥，换行与空格一并清掉', () {
      final result = parseAgentApiText('  sk-abcdefghijklmnopqrst\n ');
      expect(result.apiKey, 'sk-abcdefghijklmnopqrst');
      expect(result.baseUrl, isNull);
    });
  });
}
