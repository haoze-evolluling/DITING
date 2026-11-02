/// AI analysis layer: client, model listing, connectivity test and the state machine for one run.
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
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Real OpenAI-compatible client; tests inject a fake via `overrideWithValue`. Rebuilds when the
/// `/config/user-agents` selection changes, so a gateway that filters on UA sees the chosen one.
final agentApiClientProvider = Provider<AgentApiClient>(
  (ref) => AgentApiClient(userAgent: ref.watch(requestUserAgentProvider)),
);

/// Active provider as [AgentChatConfig]; null when no key is configured.
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

/// One analysis run. [sessionId] identifies it: results are only written back when the id still
/// matches, so a slow first request cannot overwrite a newer one (which the previous single-slot
/// state allowed, showing the wrong domain's report).
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

  /// 0 when no run has happened in this process.
  final int sessionId;
  final AgentAnalysisTarget? target;
  final AgentAnalysisPhase phase;

  /// Markdown report, set when [phase] is success.
  final String? content;
  final String? error;
  final String? model;
  final int totalTokens;

  /// What was sent to the model (traffic summary), so the user can audit the prompt.
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

  /// Starts one run and returns its session id. [extraContext] carries context the caller already
  /// has, e.g. blocking records.
  int start(
    AgentAnalysisTarget target, {
    List<String> extraContext = const [],
  }) {
    final session = ++_nextSession;
    // A new run supersedes the previous one; leaving its socket open would waste tokens.
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
      state = AgentAnalysisState(
        sessionId: session,
        target: target,
        phase: AgentAnalysisPhase.failure,
        error: currentL10n.agentApiKeyMissing,
        startedAt: state.startedAt,
      );
      return session;
    }
    // Fire and forget: the UI watches the state, and the guard below keeps a stale answer out.
    _run(session, target, config, extraContext, cancelToken);
    return session;
  }

  void cancel() {
    _cancelToken?.cancel();
    _cancelToken = null;
    state = const AgentAnalysisState();
  }

  void clear() {
    _cancelToken?.cancel();
    _cancelToken = null;
    state = const AgentAnalysisState();
  }

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
      if (state.sessionId != session) return;
      state = AgentAnalysisState(
        sessionId: session,
        target: target,
        phase: AgentAnalysisPhase.failure,
        error: error.message,
        promptDigest: state.promptDigest,
        startedAt: state.startedAt,
      );
    } on Object catch (error) {
      // Never leave the UI spinning: turn unknown errors into a readable message.
      if (state.sessionId != session) return;
      state = AgentAnalysisState(
        sessionId: session,
        target: target,
        phase: AgentAnalysisPhase.failure,
        error: currentL10n.agentAnalysisFailed('$error'),
        promptDigest: state.promptDigest,
        startedAt: state.startedAt,
      );
    }
  }

  Future<AgentAnalysisRequest> _buildRequest(
    int session,
    AgentAnalysisTarget target,
    AgentChatConfig config,
    List<String> extraContext,
  ) async {
    final db = await ref.read(activeLogDatabaseProvider.future);
    final express = ref.read(workModeProvider) == AppWorkMode.express;
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
          // Without the legacy DB this feature is unavailable, not "no traffic".
          throw AgentApiException(
            currentL10n.agentNoLegacyDatabase,
          );
        }
        final summary = await summarizeRecentTraffic(
          dnsRepository: DnsLogRepository(db),
          httpRepository: express ? null : HttpRequestRepository(db),
          httpUnavailableReason: express
              ? currentL10n.agentExpressNoHttps
              : null,
        );
        // Recorded before the request so the "查看送检摘要" panel has it while running. Guarded:
        // a superseded run must not overwrite the digest of the one that replaced it.
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

/// Fetches the model list for the current dialog; one-shot user action, so it stays out of a
/// provider.
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
