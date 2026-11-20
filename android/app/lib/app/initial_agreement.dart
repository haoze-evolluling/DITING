library;

import 'dart:ui' show ImageFilter;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/state/settings_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class InitialAgreementGate extends ConsumerStatefulWidget {
  const InitialAgreementGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<InitialAgreementGate> createState() =>
      _InitialAgreementGateState();
}

class _InitialAgreementGateState extends ConsumerState<InitialAgreementGate> {
  var _declined = false;

  @override
  Widget build(BuildContext context) {
    final accepted = ref.watch(initialAgreementProvider);
    if (accepted) {
      return widget.child;
    }
    return Stack(
      children: [
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
                style: AppTextRole.rowTitle.of(context),
              ),
              Text(
                context.l10n.agreementDeclinedMessage,
                style: AppTextRole.supportingText.of(context),
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
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.5,
        ),
        child: SingleChildScrollView(
          child: Text(
            context.l10n.agreementMessage,
            style: AppTextRole.legalText.of(context),
          ),
        ),
      ),
    );
  }
}
