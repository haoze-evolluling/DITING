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

/// Quick presets shown above the custom entry in the duration menu. Any other length is typed into
/// the custom dialog, so the pause is no longer limited to these three values.
const _presetMinutes = <int>[15, 30, 60];

/// Bounds of a custom pause: one minute up to a full day.
const _minPauseMinutes = 1;
const _maxPauseMinutes = 1440;

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

  Future<void> _pause(int minutes) => _run((bridge) => bridge.pause(minutes));

  /// The custom entry in the menu: collect a minute count first, then pause. The popup has already
  /// dismissed by the time its item runs, so the dialog opens over the page.
  Future<void> _pickCustomMinutes() async {
    final minutes = await showFloatingDialog<int>(
      context: context,
      child: const _CustomPauseDialog(),
    );
    if (minutes == null || !mounted) return;
    await _pause(minutes);
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
          _PauseDurationCard(
            busy: _busy,
            onPause: (minutes) => _pause(minutes),
            onCustom: _pickCustomMinutes,
          ),
          _paddedCard(
            context,
            ListItem.toggle(
              padding: EdgeInsets.zero,
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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

/// The pause control: one tappable row that opens the duration menu, instead of a row of preset
/// buttons. The row fills its card so the pressed ink follows the card's rounded corners.
class _PauseDurationCard extends StatelessWidget {
  const _PauseDurationCard({
    required this.busy,
    required this.onPause,
    required this.onCustom,
  });

  final bool busy;
  final ValueChanged<int> onPause;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    PopupOpen? openMenu;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: CommonCard(
        child: ListItem(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          leading: const GlyphIcon(AppGlyphs.clock, size: 22),
          title: Text(l10n.blockPauseDurationTitle),
          subtitle: Text(l10n.blockPauseDurationSubtitle),
          onTap: busy ? null : () => openMenu?.call(),
          trailing: CommonPopupBox(
            targetBuilder: (open) {
              openMenu = open;
              return TextButton(
                onPressed: busy ? null : open,
                style: TextButton.styleFrom(
                  foregroundColor: context.colorScheme.onSurfaceVariant,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const GlyphIcon(AppGlyphs.picker),
              );
            },
            popupBuilder: (_) => CommonPopupMenu(
              items: [
                for (final minutes in _presetMinutes)
                  CommonPopupMenuItem(
                    label: l10n.blockPausePresetOption(minutes),
                    glyph: AppGlyphs.clock,
                    onPressed: busy ? null : () => onPause(minutes),
                  ),
                CommonPopupMenuItem(
                  label: l10n.blockPauseCustomOption,
                  glyph: AppGlyphs.edit,
                  // Set the custom entry apart below a divider, as an iOS menu does.
                  section: const CommonPopupMenuSection(),
                  onPressed: busy ? null : onCustom,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for a pause length in whole minutes, bounded to a day. Kept alive across the dialog's exit
/// animation; disposing the controller right after `await` trips a framework assertion.
class _CustomPauseDialog extends StatefulWidget {
  const _CustomPauseDialog();

  @override
  State<_CustomPauseDialog> createState() => _CustomPauseDialogState();
}

class _CustomPauseDialogState extends State<_CustomPauseDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_controller.text.trim());
    if (value == null || value < _minPauseMinutes || value > _maxPauseMinutes) {
      setState(() => _error = context.l10n.blockPauseMinutesInvalid);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: context.l10n.blockPauseCustomTitle,
      hasFields: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.uiCancel),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(context.l10n.commonSave),
        ),
      ],
      child: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: context.l10n.blockPauseMinutesLabel,
          helperText: context.l10n.blockPauseMinutesHelper,
          errorText: _error,
        ),
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
    return _paddedCard(
      context,
      Row(
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

Widget _paddedCard(BuildContext context, Widget child) => Padding(
  // A top inset so stacked cards read as separate surfaces; without it they butt
  // together and pinch into one column.
  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
  child: CommonCard(padding: const EdgeInsets.all(16), child: child),
);
