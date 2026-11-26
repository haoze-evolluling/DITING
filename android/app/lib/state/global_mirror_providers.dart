library;

import 'package:diting_android/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/subscriptions/subscription_url.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GlobalMirrorState {
  const GlobalMirrorState({required this.enabled, this.template});

  final bool enabled;

  final String? template;

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

  void setEnabled(bool value, {String? fallbackTemplate}) => _write((settings) {
    settings.setGlobalMirrorEnabled(value);
    if (value && fallbackTemplate != null) {
      settings.setGlobalMirrorTemplate(fallbackTemplate);
    }
  });

  void select(String template) =>
      _write((settings) => settings.setGlobalMirrorTemplate(template));

  void templateChanged(String from, String to) {
    if (state.template == from && from != to) {
      select(to);
    }
  }

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

final globalMirrorTemplateProvider = Provider<String?>(
  (ref) => ref.watch(globalMirrorProvider).effectiveTemplate,
);

String? globalMirrorUrl(String? template, String url) {
  if (template == null) return null;
  try {
    return buildMirrorUrl(template, url);
  } on FormatException {
    return null;
  }
}
