/// A11 state: outbound webhook settings and the dispatcher actions.
library;

import 'package:diting_android/data/db/automation_models.dart';
import 'package:diting_android/data/webhook/webhook_dispatcher.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WebhookSettings {
  const WebhookSettings({
    required this.enabled,
    required this.url,
    required this.secret,
  });

  final bool enabled;
  final String url;
  final String secret;

  WebhookSettings copyWith({bool? enabled, String? url, String? secret}) =>
      WebhookSettings(
        enabled: enabled ?? this.enabled,
        url: url ?? this.url,
        secret: secret ?? this.secret,
      );

  bool get isConfigured => url.trim().isNotEmpty;
}

class WebhookNotifier extends Notifier<WebhookSettings> {
  @override
  WebhookSettings build() {
    final settings = ref.read(legacySettingsProvider);
    return WebhookSettings(
      enabled: settings.webhookEnabled,
      url: settings.webhookUrl,
      secret: settings.webhookSecret,
    );
  }

  void setEnabled(bool value) {
    ref.read(legacySettingsProvider).setWebhookEnabled(value);
    state = state.copyWith(enabled: value);
  }

  void setUrl(String value) {
    ref.read(legacySettingsProvider).setWebhookUrl(value);
    state = state.copyWith(url: value);
  }

  void setSecret(String value) {
    ref.read(legacySettingsProvider).setWebhookSecret(value);
    state = state.copyWith(secret: value);
  }
}

final webhookSettingsProvider =
    NotifierProvider<WebhookNotifier, WebhookSettings>(WebhookNotifier.new);

/// The dispatcher the app and the test button share; a fresh one is cheap.
final webhookDispatcherProvider = Provider<WebhookDispatcher>(
  (ref) => WebhookDispatcher(),
);

class WebhookActions {
  const WebhookActions(this._ref);

  final Ref _ref;

  WebhookSettings get _settings => _ref.read(webhookSettingsProvider);

  /// Sends a `test` event so a user can verify the endpoint and signature before relying on it.
  Future<WebhookDeliveryResult> sendTest() {
    final settings = _settings;
    return _ref.read(webhookDispatcherProvider).deliver(
      url: settings.url,
      secret: settings.secret,
      payload: {
        'event': 'test',
        'outcome': 'ping',
        'ruleId': '',
        'ts': DateTime.now().millisecondsSinceEpoch,
        'detail': const <String, Object?>{},
      },
    );
  }

  /// Mirrors an audit event when the webhook is enabled. Failures are swallowed: a broken webhook
  /// must never fail the action it is reporting.
  Future<void> dispatch(AutomationEvent event) async {
    final settings = _settings;
    if (!settings.enabled || !settings.isConfigured) return;
    await _ref.read(webhookDispatcherProvider).deliver(
      url: settings.url,
      secret: settings.secret,
      payload: {
        'event': event.event,
        'outcome': event.outcome,
        'ruleId': event.ruleId,
        'ts': event.ts,
        'detail': event.detail,
      },
    );
  }
}

final webhookActionsProvider = Provider<WebhookActions>(WebhookActions.new);
