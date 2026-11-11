/// OpenAI-compatible chat client. Endpoints: DeepSeek `https://api.deepseek.com`, Zhipu
/// `.../api/paas/v4`, SiliconFlow `.../v1`.
///
/// The transport is here (sockets, timeouts, cancellation); everything that decides what is sent and
/// what the answer means is in `rust/diting-agent-core/src/api.rs`. Failures come back as kinds so
/// the sentences below stay in the app's localisation.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:diting_android/data/agent/rust_agent_core.dart';
import 'package:diting_android/data/http/request_user_agent.dart';
import 'package:diting_shared/app/l10n/l10n.dart';

class AgentChatMessage {
  const AgentChatMessage({required this.role, required this.content});

  final String role;
  final String content;
}

class AgentChatResult {
  const AgentChatResult({
    required this.content,
    required this.model,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
  });

  final String content;
  final String model;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  bool get hasUsage => totalTokens > 0;
}

class AgentApiException implements Exception {
  const AgentApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Cancels one in-flight request by force-closing its socket. A model answer takes tens of seconds,
/// so "stop waiting" has to interrupt the request rather than just ignore its result; streaming
/// would be the other answer, but it rewrites the transport and every fake-server test for a purely
/// cosmetic gain.
class AgentCancelToken {
  bool _cancelled = false;
  void Function()? _onCancel;

  bool get isCancelled => _cancelled;

  /// Throws [AgentApiException] when the token was already cancelled, so callers cannot start a
  /// request that is doomed from the start.
  void throwIfCancelled() {
    if (_cancelled) throw AgentApiException(currentL10n.agentApiCancelled);
  }

  void _register(void Function() onCancel) {
    _onCancel = onCancel;
    // Cancelled while the socket was being opened: honour it now.
    if (_cancelled) onCancel();
  }

  void _unregister() => _onCancel = null;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel?.call();
    _onCancel = null;
  }
}

class AgentChatConfig {
  const AgentChatConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.temperature = 0.7,
    this.systemPrompt = '',
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final double temperature;
  final String systemPrompt;

  bool get hasKey => apiKey.trim().isNotEmpty;
}

class AgentApiClient {
  const AgentApiClient({
    this.connectTimeout = const Duration(seconds: 15),
    this.readTimeout = const Duration(seconds: 45),
    this.modelsTimeout = const Duration(seconds: 20),
    this.userAgent = appFallbackUserAgent,
  });

  final Duration connectTimeout;
  final Duration readTimeout;
  final Duration modelsTimeout;

  /// `/config/user-agents` override; some gateways reject the default one.
  final String userAgent;

  /// Base URL to `/chat/completions`; OpenAI and DeepSeek need the `/v1` segment.
  static String resolveChatCompletionsEndpoint(String rawBaseUrl) =>
      _endpoint(() => RustAgentCore.instance.chatEndpoint(rawBaseUrl));

  static String resolveModelsEndpoint(String rawBaseUrl) =>
      _endpoint(() => RustAgentCore.instance.modelsEndpoint(rawBaseUrl));

  /// The kernel reports a blank address as a kind; the sentence is the app's.
  static String _endpoint(String Function() resolve) {
    try {
      return resolve();
    } on AgentKernelException catch (error) {
      if (error.failure == AgentKernelFailure.emptyEndpoint) {
        throw AgentApiException(currentL10n.agentApiEmptyEndpoint);
      }
      rethrow;
    }
  }

  /// Model list. Never hardcoded (it goes stale); `data`, `models` and `result` shapes are all
  /// accepted.
  Future<List<String>> fetchModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    final endpoint = resolveModelsEndpoint(baseUrl);
    final body = await _sendJson(
      method: 'GET',
      url: endpoint,
      apiKey: apiKey,
      timeout: modelsTimeout,
    );
    try {
      return RustAgentCore.instance.parseModels(body);
    } on AgentKernelException catch (error) {
      throw switch (error.failure) {
        // `jsonDecode` used to surface this one as-is.
        AgentKernelFailure.invalidJson => const FormatException('响应不是合法的 JSON'),
        AgentKernelFailure.noModelListJson => AgentApiException(
          currentL10n.agentApiNoModelListJson,
        ),
        AgentKernelFailure.noModelListData => AgentApiException(
          currentL10n.agentApiNoModelListData,
        ),
        AgentKernelFailure.noModels => AgentApiException(
          currentL10n.agentApiNoModels,
        ),
        _ => AgentApiException(currentL10n.agentApiNoModelListJson),
      };
    }
  }

  /// Connectivity probe: one very short message, to check key and model name.
  Future<AgentChatResult> testConnection(AgentChatConfig config) {
    if (!config.hasKey) {
      throw AgentApiException(currentL10n.agentApiKeyEmpty);
    }
    return chat(
      config,
      const [
        AgentChatMessage(
          role: 'user',
          content:
              'Hi, this is a connectivity test from DITING. '
              "Please reply with 'OK' and your model name in 10 words.",
        ),
      ],
      temperatureOverride: 0.1,
      timeout: const Duration(seconds: 15),
    );
  }

  Future<AgentChatResult> chat(
    AgentChatConfig config,
    List<AgentChatMessage> messages, {
    double? temperatureOverride,
    Duration? timeout,
    AgentCancelToken? cancelToken,
  }) async {
    if (!config.hasKey) {
      throw AgentApiException(currentL10n.agentApiKeyEmptyHint);
    }
    final endpoint = resolveChatCompletionsEndpoint(config.baseUrl);
    final payload = RustAgentCore.instance.chatBody(
      model: config.model,
      messages: [
        for (final message in messages)
          (role: message.role, content: message.content),
      ],
      temperature: temperatureOverride ?? config.temperature,
    );
    final body = await _sendJson(
      method: 'POST',
      url: endpoint,
      apiKey: config.apiKey,
      payload: payload,
      timeout: timeout ?? readTimeout,
      cancelToken: cancelToken,
    );
    return _parseChat(body, fallbackModel: config.model);
  }

  AgentChatResult _parseChat(String body, {required String fallbackModel}) {
    try {
      final reply = RustAgentCore.instance.parseChat(
        body,
        fallbackModel: fallbackModel,
      );
      return AgentChatResult(
        content: reply.content,
        model: reply.model,
        promptTokens: reply.promptTokens,
        completionTokens: reply.completionTokens,
        totalTokens: reply.totalTokens,
      );
    } on AgentKernelException catch (error) {
      throw switch (error.failure) {
        // `jsonDecode` used to surface this one as-is.
        AgentKernelFailure.invalidJson => const FormatException('响应不是合法的 JSON'),
        AgentKernelFailure.notJsonObject => AgentApiException(
          currentL10n.agentApiResponseNotJsonObject,
        ),
        AgentKernelFailure.emptyContent => AgentApiException(
          currentL10n.agentApiEmptyContent,
        ),
        _ => AgentApiException(currentL10n.agentApiEmptyContent),
      };
    }
  }

  Future<String> _sendJson({
    required String method,
    required String url,
    required String apiKey,
    String? payload,
    required Duration timeout,
    AgentCancelToken? cancelToken,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      throw AgentApiException(currentL10n.agentApiBadUrl(url));
    }
    final client = HttpClient()..connectionTimeout = connectTimeout;
    cancelToken?.throwIfCancelled();
    // Closing the client is the only way to abort a pending read; the awaits below then fail with
    // a socket/HTTP error, which is mapped back to "cancelled" in the catch blocks.
    cancelToken?._register(() => client.close(force: true));
    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      if (apiKey.trim().isNotEmpty) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${apiKey.trim()}',
        );
      }
      if (payload != null) {
        final bytes = utf8.encode(payload);
        request.headers.contentType = ContentType(
          'application',
          'json',
          charset: 'utf-8',
        );
        request.contentLength = bytes.length;
        request.add(bytes);
      }
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AgentApiException(
          _describe(status: response.statusCode, body: body),
        );
      }
      return body;
    } on AgentApiException {
      rethrow;
    } on Object catch (error) {
      // A cancelled request surfaces as SocketException/HttpException from the closed client.
      if (cancelToken?.isCancelled ?? false) {
        throw AgentApiException(currentL10n.agentApiCancelled);
      }
      if (error is TimeoutException) {
        throw AgentApiException(currentL10n.agentApiTimeout);
      }
      if (error is SocketException) {
        throw AgentApiException(
          currentL10n.agentApiUnreachable(
            error.osError?.message ?? error.message,
          ),
        );
      }
      if (error is HandshakeException) {
        throw AgentApiException(currentL10n.agentApiTls);
      }
      if (error is FormatException) {
        throw AgentApiException(currentL10n.agentApiInvalidJson);
      }
      rethrow;
    } finally {
      cancelToken?._unregister();
      client.close(force: true);
    }
  }

  /// HTTP status plus server `error.message` becomes an actionable sentence.
  static String _describe({required int status, required String body}) {
    final result = RustAgentCore.instance.describeStatus(status, body);
    final hint = switch (result.kind) {
      AgentStatusKind.badKey => currentL10n.agentApiBadKey,
      AgentStatusKind.noAccess => currentL10n.agentApiNoAccess,
      AgentStatusKind.modelNotFound => currentL10n.agentApiModelNotFound,
      AgentStatusKind.rateLimited => currentL10n.agentApiRateLimited,
      AgentStatusKind.unavailable => currentL10n.agentApiUnavailable(status),
      AgentStatusKind.requestFailed => currentL10n.agentApiRequestFailed(
        status,
      ),
    };
    final detail = result.detail;
    return detail == null
        ? hint
        : '$hint${currentL10n.agentApiServerDetail(detail)}';
  }
}
