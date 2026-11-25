library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/agent/agent_analysis_target.dart';
import 'package:diting_android/data/agent/agent_api_client.dart';
import 'package:diting_android/data/agent/agent_prompts.dart';
import 'package:diting_android/data/agent/agent_traffic_summary.dart';
import 'package:diting_android/data/db/dns_log_repository.dart';
import 'package:diting_android/data/db/http_request_repository.dart';
import 'package:diting_android/state/config_providers_resources.dart';
import 'package:diting_android/state/hub_settings_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final agentApiClientProvider = Provider<AgentApiClient>(
  (ref) => AgentApiClient(userAgent: ref.watch(requestUserAgentProvider)),
);

final agentChatConfigProvider = Provider<AgentChatConfig?>((ref) {
  final state = ref.watch(agentApiProvider);
  final provider = state.activeProvider;
  if (provider == null) return null;
  return AgentChatConfig(
    baseUrl: provider.baseUrl,
    apiKey: provider.apiKey,
    model: provider.model,
    temperature: state.temperature,
    systemPrompt: state.systemPrompt,
  );
});

enum AgentAnalysisPhase { idle, running, success, failure }

class AgentAnalysisState {
  const AgentAnalysisState({
    this.sessionId = 0,
    this.target,
    this.phase = AgentAnalysisPhase.idle,
    this.content,
    this.error,
    this.model,
    this.totalTokens = 0,
    this.promptDigest,
    this.startedAt,
  });

  final int sessionId;
  final AgentAnalysisTarget? target;
  final AgentAnalysisPhase phase;

  final String? content;
  final String? error;
  final String? model;
  final int totalTokens;

  final String? promptDigest;
  final DateTime? startedAt;

  bool get idle => phase == AgentAnalysisPhase.idle;
  bool get running => phase == AgentAnalysisPhase.running;
  bool get success => phase == AgentAnalysisPhase.success;
  bool get failed => phase == AgentAnalysisPhase.failure;
}

class AgentAnalysisNotifier extends Notifier<AgentAnalysisState> {
  int _nextSession = 0;
  AgentCancelToken? _cancelToken;

  @override
  AgentAnalysisState build() => const AgentAnalysisState();

  int start(
    AgentAnalysisTarget target, {
    List<String> extraContext = const [],
  }) {
    final session = ++_nextSession;
    _cancelToken?.cancel();
    final cancelToken = AgentCancelToken();
    _cancelToken = cancelToken;
    final config = ref.read(agentChatConfigProvider);
    state = AgentAnalysisState(
      sessionId: session,
      target: target,
      phase: AgentAnalysisPhase.running,
      startedAt: DateTime.now(),
    );
    if (config == null || !config.hasKey) {
      _fail(session, target, currentL10n.agentApiKeyMissing);
      return session;
    }
    _run(session, target, config, extraContext, cancelToken);
    return session;
  }

  void cancel() {
    _cancelToken?.cancel();
    _cancelToken = null;
    state = const AgentAnalysisState();
  }

  void clear() => cancel();

  Future<void> _run(
    int session,
    AgentAnalysisTarget target,
    AgentChatConfig config,
    List<String> extraContext,
    AgentCancelToken cancelToken,
  ) async {
    try {
      final request = await _buildRequest(
        session,
        target,
        config,
        extraContext,
      );
      if (state.sessionId != session) return;
      final result = await ref.read(agentApiClientProvider).chat(config, [
        AgentChatMessage(role: 'system', content: request.systemPrompt),
        AgentChatMessage(role: 'user', content: request.userPrompt),
      ], cancelToken: cancelToken);
      if (state.sessionId != session) return;
      state = AgentAnalysisState(
        sessionId: session,
        target: target,
        phase: AgentAnalysisPhase.success,
        content: result.content,
        model: result.model,
        totalTokens: result.totalTokens,
        promptDigest: state.promptDigest,
        startedAt: state.startedAt,
      );
    } on AgentApiException catch (error) {
      _fail(session, target, error.message);
    } on Object catch (error) {
      _fail(session, target, currentL10n.agentAnalysisFailed('$error'));
    }
  }

  void _fail(int session, AgentAnalysisTarget target, String error) {
    if (state.sessionId != session) return;
    state = AgentAnalysisState(
      sessionId: session,
      target: target,
      phase: AgentAnalysisPhase.failure,
      error: error,
      promptDigest: state.promptDigest,
      startedAt: state.startedAt,
    );
  }

  Future<AgentAnalysisRequest> _buildRequest(
    int session,
    AgentAnalysisTarget target,
    AgentChatConfig config,
    List<String> extraContext,
  ) async {
    final db = await ref.read(activeLogDatabaseProvider.future);
    switch (target) {
      case AgentDomainTarget(:final domain, :final contextLogs):
        final logs = <String>[...contextLogs, ...extraContext];
        if (db != null) {
          final recent = await DnsLogRepository(db).recent(limit: 200);
          final lowered = domain.toLowerCase();
          for (final row in recent) {
            if (logs.length >= 8) break;
            if (!row.domain.toLowerCase().contains(lowered)) continue;
            final message = row.message;
            logs.add(
              'DNS: ${row.domain} -> ${row.result}'
              '${message == null || message.isEmpty ? currentL10n.agentNoExtraInfo : '（$message）'}',
            );
          }
        }
        return buildDomainAnalysisRequest(
          domain: domain,
          systemPrompt: config.systemPrompt,
          context: logs.isEmpty ? null : logs.join('\n'),
        );
      case AgentTrafficTarget():
        if (db == null) {
          throw AgentApiException(currentL10n.agentNoLogDatabase);
        }
        final summary = await summarizeRecentTraffic(
          dnsRepository: DnsLogRepository(db),
          httpRepository: HttpRequestRepository(db),
        );
        if (state.sessionId == session) {
          state = AgentAnalysisState(
            sessionId: state.sessionId,
            target: state.target,
            phase: state.phase,
            promptDigest: summary.render(),
            startedAt: state.startedAt,
          );
        }
        return buildTrafficAnalysisRequest(
          summary: summary,
          systemPrompt: config.systemPrompt,
        );
    }
  }
}

final agentAnalysisProvider =
    NotifierProvider<AgentAnalysisNotifier, AgentAnalysisState>(
      AgentAnalysisNotifier.new,
    );

Future<List<String>> fetchAgentModels(
  WidgetRef ref, {
  required String baseUrl,
  required String apiKey,
}) => ref
    .read(agentApiClientProvider)
    .fetchModels(baseUrl: baseUrl, apiKey: apiKey);

Future<AgentChatResult> testAgentConnection(
  WidgetRef ref,
  AgentChatConfig config,
) => ref.read(agentApiClientProvider).testConnection(config);
