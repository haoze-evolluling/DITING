library;

import 'dart:ui' show ImageFilter;

import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/state/settings_providers.dart';
import 'package:diting_android/ui/ui.dart';
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
      padding: const EdgeInsets.fromLTRB(30, 8, 30, 16),
      titleAlign: TextAlign.center,
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
      child: _AgreementBody(message: context.l10n.agreementMessage),
    );
  }
}

class _AgreementBody extends StatefulWidget {
  const _AgreementBody({required this.message});

  final String message;

  @override
  State<_AgreementBody> createState() => _AgreementBodyState();
}

class _AgreementBodyState extends State<_AgreementBody> {
  final _scrollController = ScrollController();
  var _atStart = true;
  var _atEnd = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_syncFade);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFade());
  }

  @override
  void didUpdateWidget(_AgreementBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncFade());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _syncFade() {
    if (!mounted) {
      return;
    }
    final position = _scrollController.hasClients
        ? _scrollController.position
        : null;
    final atStart = position == null || position.pixels <= 0.5;
    final atEnd =
        position == null || position.maxScrollExtent - position.pixels <= 0.5;
    if (atStart != _atStart || atEnd != _atEnd) {
      setState(() {
        _atStart = atStart;
        _atEnd = atEnd;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.5,
      ),
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _atStart ? Colors.white : Colors.transparent,
            Colors.white,
            Colors.white,
            _atEnd ? Colors.white : Colors.transparent,
          ],
          stops: const [0.0, 0.05, 0.94, 1.0],
        ).createShader(bounds),
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.only(bottom: 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 16,
            children: [
              for (final section in _parseSections(widget.message))
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 6,
                  children: [
                    Text(
                      section.title,
                      style: AppTextRole.bodyStrong.of(context),
                    ),
                    Text(
                      section.body,
                      style: AppTextRole.legalText.of(context),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgreementSection {
  const _AgreementSection({required this.title, required this.body});

  final String title;
  final String body;
}

List<_AgreementSection> _parseSections(String message) {
  final sections = <_AgreementSection>[];
  for (final raw in message.split(RegExp(r'\n\s*\n'))) {
    final block = raw.trim();
    if (block.isEmpty) {
      continue;
    }
    final lines = block.split('\n');
    sections.add(
      _AgreementSection(
        title: lines.first.trim(),
        body: lines.skip(1).join('\n').trim(),
      ),
    );
  }
  return sections;
}
