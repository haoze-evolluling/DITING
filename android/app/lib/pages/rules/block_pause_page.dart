/// Temporary pause + allowlist-only (R4): the "light control" page.
///
/// Pausing skips every policy block (DNS still resolves) until the wall-clock deadline; resuming
/// clears it. Allowlist-only blocks anything that is not an explicit allow. All enforcement is in
/// the Rust engine; this page only drives the Kotlin bridge and shows a countdown.
library;

import 'dart:async';

import 'package:diting_android/data/native/block_pause_bridge.dart';
import 'package:diting_android/state/block_pause_providers.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class BlockPausePage extends ConsumerStatefulWidget {
  const BlockPausePage({super.key});

  @override
  ConsumerState<BlockPausePage> createState() => _BlockPausePageState();
}

class _BlockPausePageState extends ConsumerState<BlockPausePage> {
  BlockPauseState? _state;
  String? _error;
  bool _busy = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Keep a 1 s tick only while paused, so a non-paused page (and a test that never reaches a real
  /// pause) schedules nothing.
  void _syncTicker() {
    if (_state?.paused ?? false) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_state?.paused ?? false) {
          setState(() {});
        } else {
          _syncTicker();
        }
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  Future<void> _load() async {
    try {
      final state = await ref.read(blockPauseBridgeProvider).read();
      if (!mounted) return;
      setState(() => _state = state);
      _syncTicker();
    } catch (_) {
      if (mounted) setState(() => _error = context.l10n.blockPauseFailed);
    }
  }

  Future<void> _run(Future<BlockPauseState> Function(BlockPauseBridge) action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final state = await action(ref.read(blockPauseBridgeProvider));
      if (mounted) {
        setState(() {
          _state = state;
          _busy = false;
        });
        _syncTicker();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = context.l10n.blockPauseFailed;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final paused = state?.paused ?? false;
    return CommonScaffold(
      title: context.l10n.blockPauseTitle,
      body: PageBody(
        children: [
          PageIntroCard(text: context.l10n.blockPauseIntro),
          _StatusCard(
            paused: paused,
            remaining: state?.remaining ?? Duration.zero,
            busy: _busy,
            onResume: () => _run((bridge) => bridge.clear()),
          ),
          CommonCard(
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final minutes in const [15, 30, 60])
                  FilledButton.tonal(
                    onPressed: _busy ? null : () => _run((b) => b.pause(minutes)),
                    child: Text(context.l10n.blockPausePresetButton(minutes)),
                  ),
              ],
            ),
          ),
          CommonCard(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.blockPauseAllowlistTitle),
              subtitle: Text(context.l10n.blockPauseAllowlistSubtitle),
              value: state?.allowlistOnly ?? false,
              onChanged: _busy
                  ? null
                  : (value) => _run((bridge) => bridge.setAllowlistOnly(value)),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                _error!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.paused,
    required this.remaining,
    required this.busy,
    required this.onResume,
  });

  final bool paused;
  final Duration remaining;
  final bool busy;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final color = paused ? scheme.warning : scheme.success;
    return CommonCard(
      child: Row(
        children: [
          GlyphIcon(
            paused ? AppGlyphs.block : AppGlyphs.checkCircle,
            size: 22,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              paused
                  ? '${context.l10n.blockPauseRunningLabel} ${_formatRemaining(remaining)}'
                  : context.l10n.blockPauseInactive,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color),
            ),
          ),
          if (paused)
            TextButton(
              onPressed: busy ? null : onResume,
              child: Text(context.l10n.blockPauseResume),
            ),
        ],
      ),
    );
  }
}

/// `M:SS` under an hour, `H:MM:SS` otherwise; the countdown only needs to feel live.
String _formatRemaining(Duration remaining) {
  String two(int value) => value.toString().padLeft(2, '0');
  final hours = remaining.inHours;
  final minutes = remaining.inMinutes % 60;
  final seconds = remaining.inSeconds % 60;
  return hours > 0
      ? '$hours:${two(minutes)}:${two(seconds)}'
      : '$minutes:${two(seconds)}';
}
