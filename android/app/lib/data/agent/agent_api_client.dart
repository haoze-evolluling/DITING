/// OpenAI-compatible chat client. Endpoints: DeepSeek `https://api.deepseek.com`, Zhipu
/// `.../api/paas/v4`, SiliconFlow `.../v1`.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:diting_android/data/http/request_user_agent.dart';

class AgentChatMessage {
  const AgentChatMessage({required this.role, required this.content});

  final String role;
  final String content;

  Map<String, Object?> toJson() => {'role': role, 'content': content};
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
  static String resolveChatCompletionsEndpoint(String rawBaseUrl) {
    final trimmed = rawBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (trimmed.isEmpty) {
      throw AgentApiException(currentL10n.agentApiEmptyEndpoint);
    }
    if (trimmed.endsWith('/chat/completions')) return trimmed;
    if (trimmed.endsWith('/v1')) return '$trimmed/chat/completions';
    if (trimmed.endsWith('/api')) return '$trimmed/v1/chat/completions';
    final lower = trimmed.toLowerCase();
    if (lower == 'https://api.openai.com' ||
        lower == 'https://api.deepseek.com') {
      return '$trimmed/v1/chat/completions';
    }
    return '$trimmed/chat/completions';
  }

  static String resolveModelsEndpoint(String rawBaseUrl) {
    final trimmed = rawBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (trimmed.isEmpty) {
      throw AgentApiException(currentL10n.agentApiEmptyEndpoint);
    }
    if (trimmed.endsWith('/chat/completions')) {
      return '${trimmed.substring(0, trimmed.length - '/chat/completions'.length)}/models';
    }
    if (trimmed.endsWith('/v1')) return '$trimmed/models';
    if (trimmed.endsWith('/api')) return '$trimmed/v1/models';
    final lower = trimmed.toLowerCase();
    if (lower == 'https://api.openai.com' ||
        lower == 'https://api.deepseek.com') {
      return '$trimmed/v1/models';
    }
    return '$trimmed/models';
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
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw AgentApiException(currentL10n.agentApiNoModelListJson);
    }
    final array = decoded['data'] ?? decoded['models'] ?? decoded['result'];
    if (array is! List) {
      throw AgentApiException(currentL10n.agentApiNoModelListData);
    }
    final ids = <String>{};
    for (final item in array) {
      String? id;
      if (item is Map) {
        for (final key in const ['id', 'model_id', 'name']) {
          final value = item[key];
          if (value is String && value.trim().isNotEmpty) {
            id = value.trim();
            break;
          }
        }
      } else if (item is String && item.trim().isNotEmpty) {
        id = item.trim();
      }
      if (id != null) ids.add(id);
    }
    if (ids.isEmpty) {
      throw AgentApiException(currentL10n.agentApiNoModels);
    }
    return ids.toList()..sort();
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
    final payload = <String, Object?>{
      'model': config.model.trim().isEmpty ? 'deepseek-flash' : config.model,
      'messages': [for (final message in messages) message.toJson()],
      'temperature': temperatureOverride ?? config.temperature,
    };
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
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw AgentApiException(currentL10n.agentApiResponseNotJsonObject);
    }
    final choices = decoded['choices'];
    String content = '';
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final message = first['message'];
        if (message is Map && message['content'] is String) {
          content = (message['content'] as String).trim();
        } else if (first['text'] is String) {
          // Completion-style endpoints put the text in `choices[].text`.
          content = (first['text'] as String).trim();
        }
      }
    }
    if (content.isEmpty) {
      throw AgentApiException(currentL10n.agentApiEmptyContent);
    }
    final usage = decoded['usage'];
    int readUsage(String key) =>
        usage is Map && usage[key] is num ? (usage[key] as num).toInt() : 0;
    final model = decoded['model'];
    return AgentChatResult(
      content: content,
      model: model is String && model.trim().isNotEmpty
          ? model.trim()
          : fallbackModel,
      promptTokens: readUsage('prompt_tokens'),
      completionTokens: readUsage('completion_tokens'),
      totalTokens: readUsage('total_tokens'),
    );
  }

  Future<String> _sendJson({
    required String method,
    required String url,
    required String apiKey,
    Map<String, Object?>? payload,
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
        final bytes = utf8.encode(jsonEncode(payload));
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
    var serverMessage = '';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) {
          serverMessage = (error['message'] as String).trim();
        } else if (decoded['message'] is String) {
          serverMessage = (decoded['message'] as String).trim();
        }
      }
    } on FormatException {
      // A non-JSON body (gateway HTML page) still maps by status code below.
    }
    final hint = switch (status) {
      401 => currentL10n.agentApiBadKey,
      403 => currentL10n.agentApiNoAccess,
      404 => currentL10n.agentApiModelNotFound,
      429 => currentL10n.agentApiRateLimited,
      >= 500 => currentL10n.agentApiUnavailable(status),
      _ => currentL10n.agentApiRequestFailed(status),
    };
    final detail = serverMessage.isEmpty
        ? ''
        : currentL10n.agentApiServerDetail(
            serverMessage.length > 200
                ? '${serverMessage.substring(0, 200)}…'
                : serverMessage,
          );
    return '$hint$detail';
  }
}
