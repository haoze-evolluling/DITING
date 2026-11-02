/// Global mirror: one switch and one template that every remote download falls back to when it has
/// no mirror of its own (subscriptions without a template, app update checks and packages).
library;

import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/subscriptions/subscription_url.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GlobalMirrorState {
  const GlobalMirrorState({required this.enabled, this.template});

  final bool enabled;

  /// Saved template string; may be set while [enabled] is off so re-enabling keeps the choice.
  final String? template;

  /// The template downloads should use, or null when off, unset or malformed.
  String? get effectiveTemplate {
    if (!enabled) return null;
    try {
      return normalizeMirrorTemplate(template);
    } on FormatException {
      return null;
    }
  }
}

class GlobalMirrorNotifier extends Notifier<GlobalMirrorState> {
  @override
  GlobalMirrorState build() {
    final settings = ref.watch(legacySettingsProvider);
    return GlobalMirrorState(
      enabled: settings.globalMirrorEnabled,
      template: settings.globalMirrorTemplate,
    );
  }

  void _write(void Function(LegacySettings settings) write) {
    write(ref.read(legacySettingsProvider));
    ref.read(legacySettingsRevisionProvider.notifier).bump();
  }

  /// Turning on with [fallbackTemplate] also selects it, for when nothing valid is chosen yet.
  void setEnabled(bool value, {String? fallbackTemplate}) => _write((settings) {
    settings.setGlobalMirrorEnabled(value);
    if (value && fallbackTemplate != null) {
      settings.setGlobalMirrorTemplate(fallbackTemplate);
    }
  });

  void select(String template) =>
      _write((settings) => settings.setGlobalMirrorTemplate(template));

  /// Keeps the global choice pointing at a template that was just edited.
  void templateChanged(String from, String to) {
    if (state.template == from && from != to) {
      select(to);
    }
  }

  /// A deleted global template turns the switch off rather than silently using a ghost row.
  void templateRemoved(String template) {
    if (state.template != template) return;
    _write((settings) {
      settings.setGlobalMirrorEnabled(false);
      settings.setGlobalMirrorTemplate('');
    });
  }
}

final globalMirrorProvider =
    NotifierProvider<GlobalMirrorNotifier, GlobalMirrorState>(
      GlobalMirrorNotifier.new,
    );

/// Template every download without its own mirror should use; null means direct.
final globalMirrorTemplateProvider = Provider<String?>(
  (ref) => ref.watch(globalMirrorProvider).effectiveTemplate,
);

/// [url] rewritten through the global mirror, or null when there is none or it cannot apply.
String? globalMirrorUrl(String? template, String url) {
  if (template == null) return null;
  try {
    return buildMirrorUrl(template, url);
  } on FormatException {
    return null;
  }
}
