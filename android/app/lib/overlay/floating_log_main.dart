library;

import 'dart:async';

import 'package:diting_android/app/bootstrap.dart';
import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/app/l10n/ui_strings.dart';
import 'package:diting_android/app/theme/colors.dart';
import 'package:diting_android/app/theme/manager.dart';
import 'package:diting_android/data/db/datasets.dart';
import 'package:diting_android/data/errors.dart';
import 'package:diting_android/data/fonts/font_repository.dart';
import 'package:diting_android/data/prefs/legacy_prefs_store.dart';
import 'package:diting_android/data/prefs/legacy_settings.dart';
import 'package:diting_android/overlay/floating_log_data.dart';
import 'package:diting_android/overlay/floating_log_panel.dart';
import 'package:diting_android/overlay/floating_log_rows.dart';
import 'package:diting_android/state/settings_providers.dart'
    show AppLanguageMode;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

Future<void> runFloatingLog() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await loadLegacyPrefsStore();
  final settings = LegacySettings(store);
  await FontRepository(settings: settings).registerAll();
  runApp(FloatingLogApp(settings: settings));
}

class FloatingLogWindowChannel {
  FloatingLogWindowChannel({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('com.haoze.diting/floating_log_window');

  final MethodChannel _channel;

  Future<void> setExpanded(
    bool expanded, {
    Size size = Size.zero,
    double dragStrip = 0,
  }) async {
    await _call('setExpanded', {
      'expanded': expanded,
      'width': size.width.round(),
      'height': size.height.round(),
      'dragStrip': dragStrip.round(),
    });
  }

  Future<void> setFocusable(bool value) =>
      _call('setFocusable', {'value': value});

  Future<void> openApp() => _call('openApp');

  Future<void> dismiss() => _call('dismiss');

  void onBack(VoidCallback handler) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'back') handler();
    });
  }

  Future<void> _call(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException {
      ignoreError();
    } on MissingPluginException {
      ignoreError();
    }
  }
}

class FloatingLogApp extends StatefulWidget {
  const FloatingLogApp({
    super.key,
    required this.settings,
    this.window,
    this.source,
  });

  final LegacySettings settings;

  final FloatingLogWindowChannel? window;
  final FloatingLogSource? source;

  @override
  State<FloatingLogApp> createState() => _FloatingLogAppState();
}

class _FloatingLogAppState extends State<FloatingLogApp> {
  final _themes = AppThemeCache();

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final pair = AppThemePair(
      seedColor: AppPalette.fromStorageValue(settings.paletteRaw).effectiveSeed,
      pureBlack: settings.pureBlackEnabled,
      fontFamily: settings.fontFamily,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      themeMode: switch (AppThemeMode.fromStorageValue(settings.themeModeRaw)) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      theme: _themes.of(pair.lightSpec),
      darkTheme: _themes.of(pair.darkSpec),
      locale: AppLanguageMode.fromStorageValue(settings.appLanguageModeRaw)
          .locale,
      localizationsDelegates: const [
        AppUiLocalizations.delegate,
        AppL10n.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppL10n.supportedLocales,
      builder: (context, child) {
        setCurrentL10n(AppL10n.of(context));
        return AppScopes(
          textScale: settings.textScale,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: FloatingLogHost(
        settings: settings,
        window: widget.window ?? FloatingLogWindowChannel(),
        source: widget.source ?? _defaultSource(settings),
      ),
    );
  }
}

FloatingLogSource _defaultSource(LegacySettings settings) {
  final dataSet = DataSet.fromWorkModeValue(settings.workModeRaw);
  return FloatingLogSource(
    databaseName: dataSet.logsDatabase,
    httpEnabled: dataSet == DataSet.normal,
  );
}

const floatingLogPanelSizes = [Size(300, 380), Size(340, 460), Size(380, 560)];

class FloatingLogHost extends StatefulWidget {
  const FloatingLogHost({
    super.key,
    required this.settings,
    required this.window,
    required this.source,
  });

  final LegacySettings settings;
  final FloatingLogWindowChannel window;
  final FloatingLogSource source;

  @override
  State<FloatingLogHost> createState() => _FloatingLogHostState();
}

class _FloatingLogHostState extends State<FloatingLogHost> {
  static const _badgeInterval = Duration(seconds: 4);

  static const _ballWindowLimit = 160.0;

  bool _expanded = false;

  bool _blank = false;
  bool _switching = false;
  late int _sizeIndex = widget.settings.floatingLogPanelSize;

  int _badge = 0;
  int _seenAt = DateTime.now().millisecondsSinceEpoch;
  Timer? _badgeTimer;
  AppLifecycleListener? _lifecycle;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    _startBadge();
  }

  @override
  void dispose() {
    _badgeTimer?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }

  void _onLifecycle(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (active == _active) return;
    _active = active;
    if (_expanded) return;
    if (active) {
      _startBadge();
    } else {
      _badgeTimer?.cancel();
    }
  }

  void _startBadge() {
    _badgeTimer?.cancel();
    if (!_active) return;
    _badgeTimer = Timer.periodic(_badgeInterval, (_) => _refreshBadge());
  }

  Future<void> _refreshBadge() async {
    final count = await widget.source.blockedSince(_seenAt);
    if (!mounted || _expanded || count == _badge) return;
    setState(() => _badge = count);
  }

  Future<void> _switchTo({required bool expanded, required Size size}) async {
    setState(() => _blank = true);
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await widget.window.setExpanded(
      expanded,
      size: size,
      dragStrip: FloatingLogPanel.headerHeight,
    );
    if (!mounted) return;
    setState(() {
      _expanded = expanded;
      _blank = false;
    });
  }

  Future<void> _expand() async {
    if (_switching || _expanded) return;
    _switching = true;
    _badgeTimer?.cancel();
    _badge = 0;
    await _switchTo(expanded: true, size: floatingLogPanelSizes[_sizeIndex]);
    _switching = false;
  }

  Future<void> _collapse() async {
    if (_switching || !_expanded) return;
    _switching = true;
    await _switchTo(expanded: false, size: Size.zero);
    _seenAt = DateTime.now().millisecondsSinceEpoch;
    _startBadge();
    _switching = false;
  }

  Future<void> _resize(int index) async {
    if (index == _sizeIndex || _switching) return;
    _switching = true;
    widget.settings.setFloatingLogPanelSize(index);
    setState(() => _sizeIndex = index);
    await _switchTo(expanded: true, size: floatingLogPanelSizes[index]);
    _switching = false;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final panelWindow = constraints.maxWidth > _ballWindowLimit;
          if (_blank || _expanded != panelWindow) {
            return const SizedBox.shrink();
          }
          if (_expanded) {
            return FloatingLogPanel(
              source: widget.source,
              window: widget.window,
              sizeIndex: _sizeIndex,
              onResize: _resize,
              onCollapse: _collapse,
            );
          }
          return Center(
            child: FloatingLogBall(badge: _badge, onTap: _expand),
          );
        },
      ),
    );
  }
}
