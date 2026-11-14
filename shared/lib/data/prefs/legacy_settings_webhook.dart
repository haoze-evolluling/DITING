part of 'legacy_settings.dart';

/// A11 webhook settings: default off, a single URL and HMAC secret. The secret is only ever read
/// by the dispatcher; the page that edits it masks the field.
extension LegacyWebhookSettings on LegacySettings {
  bool get webhookEnabled =>
      _bool(LegacySettings.uiContainer, 'webhook_enabled', false);

  void setWebhookEnabled(bool value) =>
      _store.putBool(LegacySettings.uiContainer, 'webhook_enabled', value);

  String get webhookUrl =>
      _string(LegacySettings.uiContainer, 'webhook_url') ?? '';

  void setWebhookUrl(String value) =>
      _store.putString(LegacySettings.uiContainer, 'webhook_url', value);

  String get webhookSecret =>
      _string(LegacySettings.uiContainer, 'webhook_secret') ?? '';

  void setWebhookSecret(String value) =>
      _store.putString(LegacySettings.uiContainer, 'webhook_secret', value);
}
