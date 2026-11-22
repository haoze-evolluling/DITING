library;

import 'package:diting_android/data/export/request_log_csv_exporter.dart';
import 'package:diting_android/data/export/request_log_export_options.dart';
import 'package:diting_android/state/cleanup_providers.dart';
import 'package:diting_android/state/installed_apps_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final requestLogExporterProvider = Provider<RequestLogCsvExporter>(
  (ref) => const RequestLogCsvExporter(),
);

class RequestLogExportOutcome {
  const RequestLogExportOutcome.saved(
    RequestLogExportResult this.result,
    this.name,
  ) : cancelled = false,
      error = null;

  const RequestLogExportOutcome.empty()
    : result = null,
      name = null,
      cancelled = false,
      error = null;

  const RequestLogExportOutcome.cancelled()
    : result = null,
      name = null,
      cancelled = true,
      error = null;

  const RequestLogExportOutcome.failed(String this.error)
    : result = null,
      name = null,
      cancelled = false;

  final RequestLogExportResult? result;
  final String? name;
  final bool cancelled;
  final String? error;
}

typedef RequestLogExportRunner = Future<RequestLogExportOutcome> Function(
  RequestLogExportOptions options,
);

final requestLogExportRunnerProvider = Provider<RequestLogExportRunner>(
  (ref) =>
      (options) => RequestLogExportActions(ref).exportToDocument(options),
);

class RequestLogExportActions {
  RequestLogExportActions(this._ref);

  final Ref _ref;

  Future<RequestLogExportOutcome> exportToDocument(
    RequestLogExportOptions options,
  ) async {
    final bridge = _ref.read(platformBridgeProvider);
    final begun = await bridge.beginExportDocument(
      name: 'DITING-requests-${_stampOf(DateTime.now())}.csv',
      mimeType: 'text/csv',
    );
    if (begun.cancelled) return const RequestLogExportOutcome.cancelled();
    final handle = begun.handle;
    if (handle == null) {
      return RequestLogExportOutcome.failed(
        begun.error ?? currentL10n.obsExportFailed,
      );
    }
    try {
      final dnsDb = await _ref.read(activeLogDatabaseProvider.future);
      final httpDb = _ref.read(workModeProvider).hasTunnelFeatures
          ? dnsDb
          : null;
      final installed = _ref.read(installedAppListProvider);
      final appLabels = installed == null
          ? const <String, String>{}
          : {for (final app in installed) app.packageName: app.label};
      final result = await _ref
          .read(requestLogExporterProvider)
          .exportTo(
            (chunk) async {
              final written = await bridge.appendExportChunk(
                handle: handle,
                chunk: chunk,
              );
              if (!written) throw StateError(currentL10n.obsExportFailed);
            },
            options: options,
            source: RequestLogExportSource(dnsDb: dnsDb, httpDb: httpDb),
            appLabels: appLabels,
          );
      if (result.count == 0) {
        await bridge.abortExportDocument();
        return const RequestLogExportOutcome.empty();
      }
      final saved = await bridge.endExportDocument(handle);
      if (saved.saved) {
        return RequestLogExportOutcome.saved(result, saved.name);
      }
      return RequestLogExportOutcome.failed(
        saved.error ?? currentL10n.obsExportFailed,
      );
    } catch (error) {
      await bridge.abortExportDocument();
      return RequestLogExportOutcome.failed('$error');
    }
  }

  static String _stampOf(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}'
        '-${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }
}
