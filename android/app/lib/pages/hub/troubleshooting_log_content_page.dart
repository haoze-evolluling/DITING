/// Second level of one log file: the full text. Reached from the information card in
/// [TroubleshootingLogDetailSheet]; identity alone comes from the route, so the entry survives
/// a deep link or a rebuild.
library;

import 'package:diting_android/data/native/troubleshooting_log_bridge.dart';
import 'package:diting_android/state/troubleshooting_log_providers.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class TroubleshootingLogContentPage extends ConsumerStatefulWidget {
  const TroubleshootingLogContentPage({
    super.key,
    required this.kind,
    required this.name,
  });

  final TroubleshootLogKind kind;
  final String name;

  @override
  ConsumerState<TroubleshootingLogContentPage> createState() =>
      _TroubleshootingLogContentPageState();
}

class _TroubleshootingLogContentPageState
    extends ConsumerState<TroubleshootingLogContentPage> {
  late final Future<TroubleshootLogRead> _read;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _read = ref
        .read(troubleshootingLogBridgeProvider)
        .readByName(kind: widget.kind, name: widget.name);
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    final shared = await ref
        .read(troubleshootingLogBridgeProvider)
        .shareByName(kind: widget.kind, name: widget.name);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          shared
              ? context.l10n.troubleshootLogsShared
              : context.l10n.troubleshootLogsShareFailed,
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _kindLabel() => widget.kind == TroubleshootLogKind.runtime
      ? context.l10n.troubleshootLogKindRuntime
      : context.l10n.troubleshootLogKindCrash;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    return CommonScaffold(
      title: widget.name,
      menuItems: [
        CommonPopupMenuItem(
          label: l10n.troubleshootLogsShare,
          glyph: AppGlyphs.send,
          onPressed: _busy ? null : _share,
        ),
      ],
      body: PageBody(
        children: [
          SectionBlock(
            title: l10n.troubleshootLogsLogContent,
            footer: '${_kindLabel()} · ${widget.name}',
            child: CommonCard(
              padding: const EdgeInsets.all(14),
              inert: true,
              child: FutureBuilder<TroubleshootLogRead>(
                future: _read,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CommonCircleLoading(),
                      ),
                    );
                  }
                  final result = snapshot.data ?? TroubleshootLogRead.empty;
                  final text = result.content;
                  if (text == null || text.isEmpty) {
                    return Text(
                      l10n.troubleshootLogsEmptyContent,
                      style: AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 8,
                    children: [
                      SelectableText(
                        text,
                        style: AppTextStyle.footnote
                            .of(context)
                            .copyWith(
                              color: colorScheme.onSurface,
                              fontFeatures: appTabularFigures,
                              height: 1.5,
                            ),
                      ),
                      if (result.truncated)
                        Text(
                          l10n.troubleshootLogsTruncated,
                          style: AppTextStyle.caption2
                              .of(context)
                              .copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
