// Markdown rendering and the analysis session that feeds it.

import 'dart:async';

import 'package:diting_android/data/agent/agent_analysis_target.dart';
import 'package:diting_android/data/agent/agent_api_client.dart';
import 'package:diting_android/data/agent/markdown/markdown_block.dart';
import 'package:diting_android/data/agent/markdown/markdown_inline.dart';
import 'package:diting_android/state/agent_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('Markdown 解析', _agentMarkdown);
  group('分析会话', _agentSession);
}

void _agentMarkdown() {
  group('块级解析', () {
    test('标题、段落与分隔线各归各类', () {
      final blocks = parseMarkdownBlocks('''
# 标题一

普通段落第一行
普通段落第二行

---

## 标题二
''');
      expect(blocks, hasLength(4));
      expect(
        blocks[0],
        isA<MarkdownHeading>().having((b) => b.level, 'level', 1),
      );
      expect(
        blocks[1],
        isA<MarkdownParagraph>().having(
          (b) => b.text,
          'text',
          '普通段落第一行\n普通段落第二行',
        ),
      );
      expect(blocks[2], isA<MarkdownDivider>());
      expect(
        blocks[3],
        isA<MarkdownHeading>().having((b) => b.level, 'level', 2),
      );
    });

    test('围栏代码块保留语言与内部井号行', () {
      final blocks = parseMarkdownBlocks(
        ['```dart', '# 不是标题', 'final a = 1;', '```'].join('\n'),
      );
      final code = blocks.single as MarkdownCodeBlock;
      expect(code.language, 'dart');
      expect(code.code, contains('# 不是标题'));
      expect(code.code, contains('final a = 1;'));
    });

    test('列表缩进折成层级，且有序列表保留序号', () {
      final blocks = parseMarkdownBlocks('''
- 一级
  - 二级
    - 三级
1. 第一
2. 第二
''');
      final bullets = blocks.whereType<MarkdownBulletItem>().toList();
      expect(bullets.map((b) => b.indent), [0, 1, 2]);
      final numbered = blocks.whereType<MarkdownNumberedItem>().toList();
      expect(numbered.map((b) => b.number), ['1.', '2.']);
    });

    test('表格只在有分隔行时成立，并去掉首尾空单元', () {
      final blocks = parseMarkdownBlocks('''
| 域名 | 次数 |
| --- | ---: |
| a.test | 3 |
''');
      final table = blocks.single as MarkdownTable;
      expect(table.headers, ['域名', '次数']);
      expect(table.rows, hasLength(1));
      expect(table.rows.single, ['a.test', '3']);
    });
  });

  group('内联标注', () {
    List<InlineSpan> spans(String source) =>
        buildMarkdownInlineSpans(source, _colors);

    test('链接只显示文字，不暴露地址', () {
      final text = spans('见[官方文档](https://example.test/docs)')
          .map((span) => (span as TextSpan).text)
          .join();
      expect(text, contains('官方文档'));
      expect(text, isNot(contains('https://example.test')));
    });
  });
}

const _colors = MarkdownColors(
  base: Color(0xFF000000),
  primary: Color(0xFF0000FF),
  codeBackground: Color(0xFFEEEEEE),
  error: Color(0xFFFF0000),
  tertiary: Color(0xFF00FF00),
);

/// Answers each request with a scripted delay, so two runs can finish out of order.
void _agentSession() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  ProviderContainer containerWith(List<Completer<AgentChatResult>> replies) {
    final container = ProviderContainer(
      overrides: [
        agentChatConfigProvider.overrideWithValue(_config),
        agentApiClientProvider.overrideWithValue(ScriptedClient(replies)),
        // No legacy database in a unit test: the domain branch tolerates null.
        activeLogDatabaseProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('分析会话', () {
    test('新请求取代旧请求，旧请求不再发往模型', () async {
      final reply = Completer<AgentChatResult>();
      final client = ScriptedClient([reply]);
      final container = ProviderContainer(
        overrides: [
          agentChatConfigProvider.overrideWithValue(_config),
          agentApiClientProvider.overrideWithValue(client),
          activeLogDatabaseProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(agentAnalysisProvider.notifier);

      final oldSession = notifier.start(const AgentDomainTarget('old.test'));
      final newSession = notifier.start(const AgentDomainTarget('new.test'));
      expect(newSession, greaterThan(oldSession));

      // The abandoned run is dropped before it reaches the network, so only one call is made.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(client.calls, 1);
      expect(container.read(agentAnalysisProvider).running, isTrue);

      reply.complete(
        const AgentChatResult(content: '新结论', model: 'm1', totalTokens: 2),
      );
      await Future<void>.delayed(Duration.zero);
      final state = container.read(agentAnalysisProvider);
      expect(state.success, isTrue);
      expect(state.content, '新结论');
      expect(state.sessionId, newSession);
      expect((state.target as AgentDomainTarget).domain, 'new.test');
    });

    test('取消后回到空闲，且不写错误', () async {
      final reply = Completer<AgentChatResult>();
      final container = containerWith([reply]);
      final notifier = container.read(agentAnalysisProvider.notifier);
      notifier.start(const AgentDomainTarget('a.test'));
      expect(container.read(agentAnalysisProvider).running, isTrue);

      notifier.cancel();
      final cancelled = container.read(agentAnalysisProvider);
      expect(cancelled.idle, isTrue);
      expect(cancelled.error, isNull);

      // The socket is closed, so the pending future must not resurrect the run.
      reply.complete(const AgentChatResult(content: '迟到的结论', model: 'm1'));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(agentAnalysisProvider).idle, isTrue);
    });
  });

  group('请求取消', () {
    test('已取消的令牌直接拒绝发请求', () async {
      final token = AgentCancelToken()..cancel();
      await expectLater(
        const AgentApiClient().chat(_config, const [
          AgentChatMessage(role: 'user', content: 'hi'),
        ], cancelToken: token),
        throwsA(
          isA<AgentApiException>().having(
            (error) => error.message,
            'message',
            '分析已取消',
          ),
        ),
      );
    });
  });
}

class ScriptedClient extends AgentApiClient {
  ScriptedClient(this.replies);

  final List<Completer<AgentChatResult>> replies;

  @override
  Future<AgentChatResult> chat(
    AgentChatConfig config,
    List<AgentChatMessage> messages, {
    double? temperatureOverride,
    Duration? timeout,
    AgentCancelToken? cancelToken,
  }) {
    final index = _taken++;
    return replies[index].future;
  }

  int _taken = 0;

  int get calls => _taken;
}

const _config = AgentChatConfig(
  baseUrl: 'https://api.test',
  apiKey: 'sk-test',
  model: 'm1',
);
