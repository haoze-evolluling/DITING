/// The AI report sheet, opened from a log row, a request detail or the settings test buttons.
///
/// One sheet owns one run: it records the session id returned by [AgentAnalysisNotifier.start]
/// and only shows results that belong to it, so a stale answer from a previous sheet can never
/// appear here.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/agent/agent_analysis_target.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/pages/hub/agent_markdown_view.dart';
import 'package:diting_android/routes/hub_routes.dart';
import 'package:diting_android/state/agent_providers.dart';
import 'package:diting_android/state/hub_settings_providers.dart';
import 'package:diting_android/state/rules_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/icon_badge.dart';
import 'package:diting_android/widgets/notice.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Opens the report sheet for [target]; resolves when the sheet closes.
Future<void> openAgentAnalysis(
  BuildContext context,
  AgentAnalysisTarget target,
) {
  return showSheet<void>(
    context: context,
    builder: (_) => AgentAnalysisSheet(target: target),
  );
}

class AgentAnalysisSheet extends ConsumerStatefulWidget {
  const AgentAnalysisSheet({
    super.key,
    required this.target,
    this.adoptSessionId = 0,
  });

  final AgentAnalysisTarget target;

  /// A finished session to show instead of starting a new one, used by the dashboard card so
  /// tapping it does not spend another request. Zero means "start fresh".
  final int adoptSessionId;

  @override
  ConsumerState<AgentAnalysisSheet> createState() => _AgentAnalysisSheetState();
}

class _AgentAnalysisSheetState extends ConsumerState<AgentAnalysisSheet> {
  /// Session this sheet started; results with another id are not ours to show.
  int _sessionId = 0;
  bool _showDigest = false;

  /// Feedback for the last rule write, cleared when a new run starts.
  String? _appliedAction;

  @override
  void initState() {
    super.initState();
    // The first frame has to paint before the notifier can publish a state change.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startIfReady());
  }

  void _startIfReady() {
    if (!mounted) return;
    if (widget.adoptSessionId != 0) {
      // Reuse the run the caller already has; only start over if it has been replaced since.
      final existing = ref.read(agentAnalysisProvider);
      if (existing.sessionId == widget.adoptSessionId && existing.success) {
        setState(() => _sessionId = widget.adoptSessionId);
        return;
      }
    }
    final api = ref.read(agentApiProvider);
    if (!api.enabled || !api.ready) return;
    _start();
  }

  void _start() {
    setState(() => _appliedAction = null);
    _sessionId = ref.read(agentAnalysisProvider.notifier).start(widget.target);
  }

  void _enableAndStart() {
    ref.read(agentApiProvider.notifier).setEnabled(true);
    _start();
  }

  Future<void> _copyResult(String content) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(context.l10n.agentSheetCopied)));
  }

  Future<void> _addRule(RuleKind kind) async {
    final target = widget.target;
    if (target is! AgentDomainTarget) return;
    final added = await ref
        .read(rulesProvider.notifier)
        .add(kind, target.domain);
    if (!mounted) return;
    setState(() {
      _appliedAction = added
          ? context.l10n.agentSheetRuleAdded(kind.title(context.l10n))
          : context.l10n.agentSheetRuleExists(kind.title(context.l10n));
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentAnalysisProvider);
    final api = ref.watch(agentApiProvider);
    final mine = state.sessionId == _sessionId && _sessionId != 0;
    return CommonScaffold(
      title: widget.target.title(context.l10n),
      body: ListView(
        // The sheet title floats over the body, so this top padding is required.
        padding: EdgeInsets.only(top: context.contentTopPadding, bottom: 24),
        children: [
          _Header(target: widget.target),
          ..._statusSections(context, api: api, state: state, mine: mine),
          if (mine && state.success && state.content != null) ...[
            _ResultMeta(state: state),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: AgentMarkdownView(markdown: state.content!),
            ),
            _digestSection(state),
            _resultActions(state.content!),
          ],
          if (_appliedAction case final message?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: CardNoticeRow(message: message),
            ),
          ListFooter(text: context.l10n.agentSheetFooter),
        ],
      ),
    );
  }

  List<Widget> _statusSections(
    BuildContext context, {
    required AgentApiState api,
    required AgentAnalysisState state,
    required bool mine,
  }) {
    if (!api.enabled) {
      return [
        _Notice(
          glyph: AppGlyphs.lock,
          title: context.l10n.agentSheetDisabledTitle,
          description: context.l10n.agentSheetDisabledBody,
          actionLabel: context.l10n.agentSheetEnableAndStart,
          onPressed: _enableAndStart,
        ),
      ];
    }
    if (!api.ready) {
      return [
        _Notice(
          glyph: AppGlyphs.key,
          title: context.l10n.agentSheetNoKeyTitle,
          description: context.l10n.agentSheetNoKeyBody,
          actionLabel: context.l10n.agentSheetGoConfigure,
          onPressed: () => context.push(HubPaths.agentProviders),
        ),
      ];
    }
    if (mine && state.running) {
      return [
        _Notice(
          glyph: AppGlyphs.sparkle,
          title: context.l10n.agentSheetRunning,
          description: context.l10n.agentSheetModel(
            api.activeProvider?.model ?? context.l10n.agentSheetUnknown,
          ),
          loading: true,
          actionLabel: context.l10n.uiCancel,
          onPressed: () {
            ref.read(agentAnalysisProvider.notifier).cancel();
            setState(() => _sessionId = 0);
          },
        ),
      ];
    }
    if (mine && state.failed) {
      return [
        _Notice(
          glyph: AppGlyphs.error,
          title: context.l10n.agentSheetFailed,
          description: state.error ?? context.l10n.agentSheetUnknownError,
          isError: true,
          actionLabel: context.l10n.obsRetry,
          onPressed: _start,
          secondaryLabel: context.l10n.agentSheetCheckSettings,
          onSecondaryPressed: () => context.push(HubPaths.agentProviders),
        ),
      ];
    }
    if (mine && state.success) return const [];
    // Nothing running for this sheet: either it was superseded or it never started.
    return [
      _Notice(
        glyph: AppGlyphs.sparkle,
        title: _sessionId == 0 ? context.l10n.agentSheetNotStarted : context.l10n.agentSheetSuperseded,
        description: _sessionId == 0
            ? context.l10n.agentSheetStartHint
            : context.l10n.agentSheetSupersededHint,
        actionLabel: context.l10n.agentSheetStart,
        onPressed: _start,
      ),
    ];
  }

  Widget _digestSection(AgentAnalysisState state) {
    final digest = state.promptDigest;
    if (digest == null || digest.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _showDigest = !_showDigest),
              child: Text(_showDigest ? context.l10n.agentSheetHideDigest : context.l10n.agentSheetShowDigest),
            ),
          ),
        ),
        if (_showDigest)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: ShapeDecoration(
                color: context.raisedSurfaceLevel.colorOf(context.colorScheme),
                shape: AppShape.md,
              ),
              child: SelectableText(
                digest,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(
                      fontFamily: appMonospaceFontFamily,
                      color: context.colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _resultActions(String content) {
    final target = widget.target;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          if (target is AgentDomainTarget)
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: TonalButton(
                    glyph: AppGlyphs.checkCircle,
                    label: context.l10n.agentSheetAddAllowlist,
                    onPressed: () => _addRule(RuleKind.allow),
                  ),
                ),
                Expanded(
                  child: TonalButton(
                    glyph: AppGlyphs.block,
                    label: context.l10n.agentSheetAddBlock,
                    onPressed: () => _addRule(RuleKind.block),
                  ),
                ),
              ],
            ),
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: TonalButton(
                  glyph: AppGlyphs.copy,
                  label: context.l10n.agentSheetCopyResult,
                  onPressed: () => _copyResult(content),
                ),
              ),
              Expanded(
                child: TonalButton(
                  glyph: AppGlyphs.refresh,
                  label: context.l10n.agentSheetReanalyze,
                  onPressed: _start,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.target});

  final AgentAnalysisTarget target;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        spacing: 12,
        children: [
          IconBadge(
            glyph: AppGlyphs.sparkle,
            size: 38,
            glyphSize: 20,
            color: colorScheme.primaryContainer,
            foregroundColor: colorScheme.onPrimaryContainer,
            shape: AppShape.circle,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  target.title(context.l10n),
                  style: AppTextStyle.headline.of(context, emphasized: true),
                ),
                Text(
                  target.subtitle(context.l10n),
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultMeta extends StatelessWidget {
  const _ResultMeta({required this.state});

  final AgentAnalysisState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          if (state.model case final model? when model.isNotEmpty)
            MetaChip(label: context.l10n.agentSheetModel(model)),
          if (state.totalTokens > 0)
            MetaChip(label: '${state.totalTokens} tokens'),
        ],
      ),
    );
  }
}

/// One mutually exclusive state panel: disabled, unconfigured, loading, failure or empty.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.glyph,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onPressed,
    this.secondaryLabel,
    this.onSecondaryPressed,
    this.loading = false,
    this.isError = false,
  });

  final Glyph glyph;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onPressed;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryPressed;
  final bool loading;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final accent = isError ? colorScheme.error : colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: CommonCard(
        isError: isError,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Row(
              spacing: 10,
              children: [
                if (loading)
                  const CommonCircleLoading(size: 20)
                else
                  GlyphIcon(glyph, size: 22, color: accent),
                Expanded(
                  child: Text(
                    title,
                    style: AppTextStyle.callout.of(context, emphasized: true),
                  ),
                ),
              ],
            ),
            SelectableText(
              description,
              style: context.listSubtitleStyle.copyWith(
                color: isError ? colorScheme.error : null,
              ),
            ),
            if (actionLabel != null)
              Row(
                spacing: 8,
                children: [
                  if (secondaryLabel != null)
                    Expanded(
                      child: TonalButton(
                        label: secondaryLabel!,
                        onPressed: onSecondaryPressed,
                      ),
                    ),
                  Expanded(
                    child: TonalButton(
                      glyph: isError ? AppGlyphs.refresh : null,
                      label: actionLabel!,
                      onPressed: onPressed,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
