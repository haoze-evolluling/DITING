/// One simulated lookup at a time.
///
/// The simulator has no stored state on the service: each call is a fresh judgement, so the notifier
/// keeps only the last answer and the request's own error. A new run clears the previous verdict
/// instead of letting a stale one sit beside a newer domain.
library;

import 'package:diting/desktop/data/api/desktop_api_client.dart';
import 'package:diting/desktop/data/api/desktop_api_providers.dart';
import 'package:diting/desktop/data/api/desktop_rule_check_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DesktopRuleCheckState {
  const DesktopRuleCheckState({
    this.result,
    this.error,
    this.running = false,
    this.domain = '',
    this.qtype = 'A',
  });

  final DesktopRuleCheckResult? result;
  final DesktopApiException? error;
  final bool running;

  /// The query the result belongs to, so the verdict card names the same domain that was tested.
  final String domain;
  final String qtype;
}

class DesktopRuleCheckNotifier extends Notifier<DesktopRuleCheckState> {
  @override
  DesktopRuleCheckState build() => const DesktopRuleCheckState();

  Future<void> check(String domain, String qtype) async {
    if (state.running || domain.isEmpty) return;
    state = DesktopRuleCheckState(
      running: true,
      domain: domain,
      qtype: qtype,
    );
    try {
      final result = await ref
          .read(desktopApiClientProvider)
          .checkRule(domain: domain, qtype: qtype);
      if (ref.mounted) {
        state = DesktopRuleCheckState(
          result: result,
          domain: domain,
          qtype: qtype,
        );
      }
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopRuleCheckState(
          error: error,
          domain: domain,
          qtype: qtype,
        );
      }
    }
  }
}

final desktopRuleCheckProvider =
    NotifierProvider<DesktopRuleCheckNotifier, DesktopRuleCheckState>(
      DesktopRuleCheckNotifier.new,
    );
