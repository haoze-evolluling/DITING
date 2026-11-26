library;

import 'package:diting_android/data/native/rule_test_bridge.dart';
import 'package:diting_android/state/rule_test_providers.dart';
import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class RuleTestPage extends ConsumerStatefulWidget {
  const RuleTestPage({super.key, this.initialDomain});

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

  static bool _looksLikeDomain(String value) {
    if (value.isEmpty || value.length > 253 || value.contains(' ')) {
      return false;
    }
    return value.contains('.') &&
        !value.startsWith('.') &&
        !value.endsWith('.');
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: context.l10n.ruleTestTitle,
      body: PageBody(
        children: [
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
                    Text(
                      context.l10n.toolRecordType,
                      style: AppTextRole.rowTitle.of(context),
                    ),
                    const SizedBox(width: 8),
                    PopupSelectButton<int>(
                      value: _qtype,
                      semanticLabel: context.l10n.toolRecordType,
                      items: const [(1, 'A'), (28, 'AAAA')],
                      onChanged: (value) => setState(() => _qtype = value),
                    ),
                    const Spacer(),
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
                style: AppTextRole.body
                    .of(context)
                    .copyWith(color: context.colorScheme.error),
              ),
            ),
          if (_result != null)
            _ResultCard(result: _result!)
          else if (_error == null)
            _paddedCard(
              context,
              Text(
                context.l10n.ruleTestEmptyHint,
                style: AppTextRole.body.of(context),
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
    final rewrite = result.rewrite;
    return _paddedCard(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Text(
            context.l10n.ruleTestResultTitle,
            style: AppTextRole.rowTitle.of(context),
          ),
          Row(
            children: [
              Icon(
                result.blocked ? TablerIcons.ban : TablerIcons.circle_check,
                size: 20,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTextRole.rowTitle.of(context).copyWith(color: color),
              ),
            ],
          ),
          if (matched != null)
            _ResultRow(label: context.l10n.ruleTestMatchedRule, value: matched),
          if (result.reason.isNotEmpty)
            _ResultRow(
              label: context.l10n.ruleTestReason,
              value: result.reason,
            ),
          if (rewrite != null && !rewrite.isEmpty)
            _ResultRow(
              label: context.l10n.ruleTestRewriteTitle,
              value: rewrite.entries.join('\n'),
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
          child: Text(label, style: AppTextRole.supportingText.of(context)),
        ),
        Expanded(child: Text(value, style: AppTextRole.body.of(context))),
      ],
    );
  }
}

Widget _paddedCard(BuildContext context, Widget child) => Padding(
  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
  child: CommonCard(padding: const EdgeInsets.all(16), child: child),
);
