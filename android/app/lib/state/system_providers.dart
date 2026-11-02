/// System domain: disclaimer, developer mode, WebDAV, app updates and IP quality; access control
/// lives in the pages.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'dart:async';

import 'package:diting_android/data/backup/dav_client.dart';
import 'package:diting_android/data/native/update_bridge.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/tools/ip_quality_checker.dart';
import 'package:diting_android/data/update/app_update_checker.dart';
import 'package:diting_android/state/app_version_provider.dart';
import 'package:diting_android/state/config_providers_resources.dart';
import 'package:diting_android/state/global_mirror_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum DavStatus {
  idle,
  connecting,
  connected,
  failed;

  String label(AppL10n l10n) => switch (this) {
    DavStatus.idle => l10n.davStatusIdle,
    DavStatus.connecting => l10n.davStatusConnecting,
    DavStatus.connected => l10n.davStatusConnected,
    DavStatus.failed => l10n.davStatusFailed,
  };
}

class DavState {
  const DavState({
    this.server = '',
    this.username = '',
    this.password = '',
    this.path = '/diting/',
    this.status = DavStatus.idle,
    this.message,
  });

  final String server;
  final String username;
  final String password;
  final String path;
  final DavStatus status;

  /// Failure reason; non-null only while [status] is [DavStatus.failed].
  final String? message;

  bool get isConfigured => server.isNotEmpty && username.isNotEmpty;

  DavState copyWith({
    String? server,
    String? username,
    String? password,
    String? path,
    DavStatus? status,
    String? message,
    bool clearMessage = false,
  }) => DavState(
    server: server ?? this.server,
    username: username ?? this.username,
    password: password ?? this.password,
    path: path ?? this.path,
    status: status ?? this.status,
    message: clearMessage ? null : (message ?? this.message),
  );
}

/// WebDAV connection state machine; [DavNotifier.test] performs a real request.
class DavNotifier extends Notifier<DavState> {
  @override
  DavState build() => const DavState();

  /// Built per call so a UA change in `/config/user-agents` applies to the next request.
  DavClient get _client =>
      DavClient(userAgent: ref.read(requestUserAgentProvider));

  void update(DavState Function(DavState state) update) =>
      state = update(state);

  /// Connects for real: `PROPFIND` probes, `MKCOL` creates; failures carry status and reason.
  Future<void> test() async {
    if (!state.isConfigured) {
      state = state.copyWith(
        status: DavStatus.failed,
        message: currentL10n.webdavEmptyCredentials,
      );
      return;
    }
    state = state.copyWith(status: DavStatus.connecting, clearMessage: true);
    final result = await _client.probe(
      DavCredentials(
        server: state.server,
        username: state.username,
        password: state.password,
        path: state.path,
      ),
    );
    if (result.succeeded) {
      state = state.copyWith(
        status: DavStatus.connected,
        message: result.created ? currentL10n.webdavDirectoryCreated : null,
      );
      return;
    }
    state = state.copyWith(status: DavStatus.failed, message: result.error);
  }

  void reset() => state = const DavState();

  /// Fixed name, so an upload overwrites the previous copy: sync, not archive.
  static const remoteFileName = 'diting-config.json';

  DavCredentials get credentials => DavCredentials(
    server: state.server,
    username: state.username,
    password: state.password,
    path: state.path,
  );

  /// Uploads with `PUT` to `<path>/diting-config.json`.
  Future<DavProbeResult> upload(String content) async {
    state = state.copyWith(status: DavStatus.connecting, clearMessage: true);
    final result = await _client.putText(
      credentials,
      name: remoteFileName,
      content: content,
    );
    state = result.succeeded
        ? state.copyWith(status: DavStatus.connected, message: currentL10n.webdavUploaded)
        : state.copyWith(status: DavStatus.failed, message: result.error);
    return result;
  }

  /// Downloads the cloud backup with `GET`; null when no file exists.
  Future<String?> download() async {
    state = state.copyWith(status: DavStatus.connecting, clearMessage: true);
    try {
      final text = await _client.getText(credentials, name: remoteFileName);
      state = text == null
          ? state.copyWith(status: DavStatus.connected, message: currentL10n.webdavNoBackup)
          : state.copyWith(status: DavStatus.connected, message: currentL10n.webdavDownloaded);
      return text;
    } on Object catch (error) {
      state = state.copyWith(status: DavStatus.failed, message: '$error');
      return null;
    }
  }
}

final davProvider = NotifierProvider<DavNotifier, DavState>(DavNotifier.new);

/// Disclaimer stage; some pages require restating a passage before accepting.
class DisclaimerNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void agree() => state = true;

  void reset() => state = false;
}

final disclaimerAcceptedProvider = NotifierProvider<DisclaimerNotifier, bool>(
  DisclaimerNotifier.new,
);

/// Developer-mode master switch; when off the option section is disabled. Persisted in the UI
/// container so the switch survives a restart, like every other legacy boolean.
class DeveloperModeNotifier extends Notifier<bool> {
  static const _key = 'developer_mode_enabled';

  @override
  bool build() {
    final store = ref.watch(legacyPrefsStoreProvider);
    return store.read(LegacySettings.uiContainer, _key) == true;
  }

  void toggle(bool value) {
    state = value;
    ref
        .read(legacyPrefsStoreProvider)
        .putBool(LegacySettings.uiContainer, _key, value);
    ref.read(legacySettingsRevisionProvider.notifier).bump();
  }
}

final developerModeProvider = NotifierProvider<DeveloperModeNotifier, bool>(
  DeveloperModeNotifier.new,
);

enum UpdateStage {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  downloaded;

  String label(AppL10n l10n) => switch (this) {
    UpdateStage.idle => l10n.updateStageIdle,
    UpdateStage.checking => l10n.updateStageChecking,
    UpdateStage.upToDate => l10n.updateStageUpToDate,
    UpdateStage.available => l10n.updateStageAvailable,
    UpdateStage.downloading => l10n.updateStageDownloading,
    UpdateStage.downloaded => l10n.updateStageDownloaded,
  };

  bool get isBusy => this == checking || this == downloading;
}

/// App-update state machine; [UpdateNotifier.check] queries GitHub Releases.
class UpdateState {
  const UpdateState({
    this.stage = UpdateStage.idle,
    this.progress = 0,
    this.info,
    this.currentVersion,
    this.error,
    this.apkPath,
  });

  final UpdateStage stage;

  /// 0-1; meaningful only while [UpdateStage.downloading].
  final double progress;

  /// New version found; set from [UpdateStage.available] onwards.
  final UpdateInfo? info;

  /// Local version, for the "current x to latest y" label.
  final String? currentVersion;

  /// Failure reason; non-null while idle means the last check failed.
  final String? error;

  /// Absolute path of the downloaded package; set once downloaded.
  final String? apkPath;

  UpdateState copyWith({
    UpdateStage? stage,
    double? progress,
    UpdateInfo? info,
    String? currentVersion,
    String? error,
    String? apkPath,
    bool clearError = false,
    bool clearInfo = false,
    bool clearApkPath = false,
  }) => UpdateState(
    stage: stage ?? this.stage,
    progress: progress ?? this.progress,
    info: clearInfo ? null : (info ?? this.info),
    currentVersion: currentVersion ?? this.currentVersion,
    error: clearError ? null : (error ?? this.error),
    apkPath: clearApkPath ? null : (apkPath ?? this.apkPath),
  );
}

class UpdateNotifier extends Notifier<UpdateState> {
  @override
  UpdateState build() => const UpdateState();

  /// Local version from `pubspec.yaml` ([appVersionProvider]), the only source.
  String get _currentVersion => ref.read(appVersionProvider).name;

  Future<void> check() async {
    if (state.stage.isBusy) return;
    final current = _currentVersion;
    state = state.copyWith(
      stage: UpdateStage.checking,
      progress: 0,
      currentVersion: current,
      clearError: true,
      clearInfo: true,
      clearApkPath: true,
    );
    final result = await ref.read(appUpdateCheckerProvider).check(current);
    if (result.failed) {
      // Back to idle with the reason; staying "checking" spins forever.
      state = state.copyWith(stage: UpdateStage.idle, error: result.error);
      return;
    }
    state = result.hasUpdate
        ? state.copyWith(stage: UpdateStage.available, info: result.info)
        : state.copyWith(stage: UpdateStage.upToDate, clearInfo: true);
  }

  /// Real download: the native side writes the APK and reports progress (`UpdateBridge`).
  Future<void> download() async {
    if (state.stage.isBusy) return;
    final info = state.info;
    if (info == null) {
      state = state.copyWith(error: currentL10n.updateCheckFirst);
      return;
    }
    state = state.copyWith(
      stage: UpdateStage.downloading,
      progress: 0,
      clearError: true,
      clearApkPath: true,
    );
    Future<UpdateDownloadResult> downloadFrom(String url) => ref
        .read(updateBridgeProvider)
        .download(
          url: url,
          version: info.version,
          onProgress: (progress) {
            // The user may leave or re-check mid-download, so only update while still downloading.
            if (state.stage != UpdateStage.downloading) return;
            state = state.copyWith(progress: progress.fraction ?? 0);
          },
        );
    // The global mirror goes first; a failed mirror retries the original address once.
    final mirrored = globalMirrorUrl(
      ref.read(globalMirrorTemplateProvider),
      info.downloadUrl,
    );
    var result = await downloadFrom(mirrored ?? info.downloadUrl);
    if (!result.ok &&
        mirrored != null &&
        state.stage == UpdateStage.downloading) {
      state = state.copyWith(progress: 0);
      result = await downloadFrom(info.downloadUrl);
    }
    if (!result.ok) {
      state = state.copyWith(
        stage: UpdateStage.available,
        error: result.error,
        progress: 0,
      );
      return;
    }
    state = state.copyWith(
      stage: UpdateStage.downloaded,
      progress: 1,
      apkPath: result.path,
    );
  }

  /// Launches the system installer for the downloaded package.
  Future<bool> install() async {
    final path = state.apkPath;
    if (path == null) {
      state = state.copyWith(error: currentL10n.updateDownloadFirst);
      return false;
    }
    final ok = await ref.read(updateBridgeProvider).install(path);
    if (!ok) {
      state = state.copyWith(error: currentL10n.updateInstallerUnavailable);
      return false;
    }
    return true;
  }

  void reset() => state = const UpdateState();
}

/// Update checker; tests may override the endpoint.
final appUpdateCheckerProvider = Provider<AppUpdateChecker>(
  (ref) => AppUpdateChecker(
    userAgent: ref.watch(requestUserAgentProvider),
    mirrorTemplate: ref.watch(globalMirrorTemplateProvider),
  ),
);

/// Update download/install channel, replaceable in tests.
final updateBridgeProvider = Provider<UpdateBridge>((ref) => UpdateBridge());

final updateProvider = NotifierProvider<UpdateNotifier, UpdateState>(
  UpdateNotifier.new,
);

enum IpQualityStage {
  idle,
  loading,
  loaded,
  failed;

  String label(AppL10n l10n) => switch (this) {
    IpQualityStage.idle => l10n.ipQualityStageIdle,
    IpQualityStage.loading => l10n.ipQualityStageLoading,
    IpQualityStage.loaded => l10n.ipQualityStageLoaded,
    IpQualityStage.failed => l10n.ipQualityStageFailed,
  };
}

class IpQualityState {
  const IpQualityState({
    this.stage = IpQualityStage.idle,
    this.report,
    this.error,
  });

  final IpQualityStage stage;

  /// Last successful report; kept on failure for comparison.
  final IpQualityReport? report;

  final String? error;

  IpQualityState copyWith({
    IpQualityStage? stage,
    IpQualityReport? report,
    String? error,
    bool clearError = false,
  }) => IpQualityState(
    stage: stage ?? this.stage,
    report: report ?? this.report,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Address and stage shown by the IP-quality overlay, re-detected on each open.
class IpQualityNotifier extends Notifier<IpQualityState> {
  @override
  IpQualityState build() => const IpQualityState();

  Future<void> detect() async {
    if (state.stage == IpQualityStage.loading) return;
    state = state.copyWith(stage: IpQualityStage.loading, clearError: true);
    final outcome = await ref.read(ipQualityCheckerProvider).detect();
    state = switch (outcome) {
      IpQualitySuccess(:final report) => state.copyWith(
        stage: IpQualityStage.loaded,
        report: report,
        clearError: true,
      ),
      IpQualityError(:final failure) => state.copyWith(
        stage: IpQualityStage.failed,
        error: failure.message,
      ),
    };
  }
}

/// IP-quality checker; tests may override the endpoints.
final ipQualityCheckerProvider = Provider<IpQualityChecker>(
  (ref) => IpQualityChecker(userAgent: ref.watch(requestUserAgentProvider)),
);

final ipQualityProvider = NotifierProvider<IpQualityNotifier, IpQualityState>(
  IpQualityNotifier.new,
);
