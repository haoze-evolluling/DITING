/// Rule-test simulator (R1): type a domain and qtype, see the exact verdict the engine would make.
library;

import 'package:diting_android/data/native/rule_test_bridge.dart';
import 'package:diting_android/state/rule_test_providers.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// A small page body: the query form on top, the verdict card below. All judgement lives in
/// `diting-policy-core` through the native bridge; this widget only collects input and renders the
/// answer, so a simulator result is always the engine's own.
class RuleTestPage extends ConsumerStatefulWidget {
  const RuleTestPage({super.key, this.initialDomain});

  /// 从命中排行「一键解释」带过来的域名；非空时自动跑一次。
  final String? initialDomain;

  @override
  ConsumerState<RuleTestPage> createState() => _RuleTestPageState();
}

class _RuleTestPageState extends ConsumerState<RuleTestPage> {
  final _domain = TextEditingController();
  var _qtype = 1;
  var _loading = false;
  RuleTestResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDomain?.trim() ?? '';
    if (initial.isNotEmpty) {
      _domain.text = initial;
      // 一键解释：进来就直接给出判定，省去再点一次「运行」。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _run();
      });
    }
  }

  @override
  void dispose() {
    _domain.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final domain = _domain.text.trim();
    if (!_looksLikeDomain(domain)) {
      setState(() {
        _error = context.l10n.ruleTestInvalidDomain;
        _result = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(ruleTestBridgeProvider)
          .check(domain: domain, qtype: _qtype);
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } on RuleTestException {
      if (!mounted) return;
      setState(() {
        _error = context.l10n.ruleTestFailed;
        _result = null;
        _loading = false;
      });
    }
  }

  /// A pragmatic client-side check; the engine still normalises and decides. Rejects empty input and
  /// obvious typos before a snapshot is built.
  static bool _looksLikeDomain(String value) {
    if (value.isEmpty || value.length > 253 || value.contains(' ')) return false;
    return value.contains('.') && !value.startsWith('.') && !value.endsWith('.');
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: context.l10n.ruleTestTitle,
      body: PageBody(
        children: [
          PageIntroCard(text: context.l10n.ruleTestIntro),
          _paddedCard(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                LabeledInputField(
                  label: context.l10n.ruleTestDomainLabel,
                  controller: _domain,
                  hintText: context.l10n.ruleTestDomainHint,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.search,
                  autocorrect: false,
                  onSubmitted: (_) => _run(),
                ),
                Row(
                  children: [
                    Expanded(
                      child: SegmentedControl<int>(
                        segments: const [(1, 'A'), (28, 'AAAA')],
                        value: _qtype,
                        onChanged: (value) => setState(() => _qtype = value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _loading ? null : _run,
                      child: Text(context.l10n.ruleTestRun),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _error!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.colorScheme.error,
                ),
              ),
            ),
          if (_result != null)
            _ResultCard(result: _result!)
          else if (_error == null)
            _paddedCard(
              context,
              Text(
                context.l10n.ruleTestEmptyHint,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final RuleTestResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final (label, color) = switch (result.action) {
      RuleTestAction.block => (context.l10n.ruleTestActionBlock, scheme.error),
      RuleTestAction.allow => (
        context.l10n.ruleTestActionAllow,
        scheme.success,
      ),
      RuleTestAction.pass => (context.l10n.ruleTestActionPass, scheme.success),
    };
    final matched = result.matchedRule;
    return _paddedCard(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Text(
            context.l10n.ruleTestResultTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Row(
            children: [
              GlyphIcon(
                result.blocked ? AppGlyphs.block : AppGlyphs.checkCircle,
                size: 20,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color),
              ),
            ],
          ),
          if (matched != null)
            _ResultRow(
              label: context.l10n.ruleTestMatchedRule,
              value: matched,
            ),
          if (result.reason.isNotEmpty)
            _ResultRow(label: context.l10n.ruleTestReason, value: result.reason),
          if (result.rewrite != null && !result.rewrite!.isEmpty)
            _ResultRow(
              label: context.l10n.ruleTestRewriteTitle,
              value: result.rewrite!.entries.join('\n'),
            )
          else
            _ResultRow(
              label: context.l10n.ruleTestRewriteTitle,
              value: context.l10n.ruleTestNoRewrite,
            ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        SizedBox(
          width: 96,
          child: Text(label, style: context.listCaptionStyle),
        ),
        Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    );
  }
}

Widget _paddedCard(BuildContext context, Widget child) => Padding(
  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
  child: CommonCard(padding: const EdgeInsets.all(16), child: child),
);
