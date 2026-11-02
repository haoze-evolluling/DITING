/// First-launch terms and disclaimer. 1.4.3 showed `InitialAgreementDialog` once from
/// `MainActivity` and stored `initial_agreement_accepted`; the gate mounts in `DitingApp.builder`
/// so it covers overlay routes too. Wording is verbatim from `ui/MainActivityDialogs.kt`.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'dart:ui' show ImageFilter;

import 'package:diting_shared/state/settings_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Gates the app behind the first-launch agreement; returns [child] untouched once
/// accepted, adding no layout level afterwards.
class InitialAgreementGate extends ConsumerStatefulWidget {
  const InitialAgreementGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<InitialAgreementGate> createState() =>
      _InitialAgreementGateState();
}

class _InitialAgreementGateState extends ConsumerState<InitialAgreementGate> {
  /// Set when the user declines; scoped to this run, asked again next launch.
  var _declined = false;

  @override
  Widget build(BuildContext context) {
    final accepted = ref.watch(initialAgreementProvider);
    if (accepted) {
      return widget.child;
    }
    return Stack(
      children: [
        // Blur the content behind: upstream's dialog was modal.
        ExcludeSemantics(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: widget.child,
          ),
        ),
        Positioned.fill(
          child: ColoredBox(
            color: context.colorScheme.scrim.withValues(alpha: 0.5),
          ),
        ),
        if (_declined)
          Positioned.fill(
            child: _DeclinedNotice(
              onReopen: () => setState(() => _declined = false),
            ),
          )
        else
          Positioned.fill(
            child: InitialAgreementDialog(
              onAccept: () =>
                  ref.read(initialAgreementProvider.notifier).accept(),
              onDecline: () => setState(() => _declined = true),
            ),
          ),
      ],
    );
  }
}

/// Screen shown after declining. It does not kill the process: `SystemNavigator.pop()` is treated
/// as a crash by some vendor ROMs, and "review again" keeps a mis-tap reversible.
class _DeclinedNotice extends StatelessWidget {
  const _DeclinedNotice({required this.onReopen});

  final VoidCallback onReopen;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: CommonCard(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Text(
                context.l10n.agreementDeclinedTitle,
                style: context.listTitleStyle,
              ),
              Text(
                context.l10n.agreementDeclinedMessage,
                style: context.listSubtitleStyle,
              ),
              FilledButton.tonal(
                onPressed: onReopen,
                child: Text(context.l10n.agreementReviewAgain),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The terms dialog; the wording is the verbatim upstream agreement text, now kept in the ARB
/// resources so both languages stay in one place.
class InitialAgreementDialog extends StatelessWidget {
  const InitialAgreementDialog({
    super.key,
    required this.onAccept,
    required this.onDecline,
  });

  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    // Three paragraphs of legal text are the app's longest body copy. Unlike a short question such
    // as "delete this?", it wants full width: the 20 inset plus 20 body padding widens the body by
    // ~44% on a 411dp screen.
    return CommonDialog(
      title: context.l10n.agreementTitle,
      width: double.infinity,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      actions: [
        TextButton(
          onPressed: onDecline,
          child: Text(context.l10n.agreementDecline),
        ),
        TextButton(
          onPressed: onAccept,
          child: Text(context.l10n.agreementAccept),
        ),
      ],
      // Must scroll: three paragraphs do not fit a small screen at large text. Line height 1.6
      // (default 1.33) keeps dense CJK body text legible.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.5,
        ),
        child: SingleChildScrollView(
          child: Text(
            context.l10n.agreementMessage,
            style: context.listSubtitleStyle.copyWith(height: 1.6),
          ),
        ),
      ),
    );
  }
}
