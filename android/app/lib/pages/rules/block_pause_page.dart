/// Temporary pause + allowlist-only (R4): the "light control" page.
///
/// Pausing skips every policy block (DNS still resolves) until the wall-clock deadline; resuming
/// clears it. Allowlist-only blocks anything that is not an explicit allow. All enforcement is in
/// the Rust engine; this page only drives the Kotlin bridge and shows a countdown.
library;

import 'dart:async';

import 'package:diting_android/data/native/block_pause_bridge.dart';
import 'package:diting_android/state/block_pause_providers.dart';
import 'package:diting_android/widgets/icon_badge.dart';
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
    final l10n = context.l10n;
    return CommonScaffold(
      title: l10n.blockPauseTitle,
      body: PageBody(
        children: [
          // The explainer reads as page-level help, not its own surface, so the status card below
          // is the first real thing the eye lands on.
          PageIntroText(text: l10n.blockPauseIntro),
          _StatusHero(
            paused: paused,
            remaining: state?.remaining ?? Duration.zero,
            busy: _busy,
            onResume: () => _run((bridge) => bridge.clear()),
          ),
          // One grouped surface for everything the user can change, instead of a card per control:
          // the duration picker and the allowlist switch belong to the same "pause controls".
          generateSection(
            title: l10n.blockPauseControlSectionTitle,
            items: [
              _PauseDurationRow(
                busy: _busy,
                onPause: (minutes) => _pause(minutes),
                onCustom: _pickCustomMinutes,
              ),
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.verified, size: 22),
                title: Text(l10n.blockPauseAllowlistTitle),
                subtitle: Text(l10n.blockPauseAllowlistSubtitle),
                value: state?.allowlistOnly ?? false,
                onChanged: _busy
                    ? null
                    : (value) => _run((bridge) => bridge.setAllowlistOnly(value)),
              ),
            ],
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

/// The focal status surface: a tinted badge, a headline state and a one-line hint, with the resume
/// action kept inside the same card while a pause is running.
class _StatusHero extends StatelessWidget {
  const _StatusHero({
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
    final title = paused
        ? '${context.l10n.blockPauseRunningLabel} ${_formatRemaining(remaining)}'
        : context.l10n.blockPauseInactive;
    final hint = paused
        ? context.l10n.blockPauseStatusPausedHint
        : context.l10n.blockPauseStatusActiveHint;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: CommonCard(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
        child: Row(
          spacing: 12,
          children: [
            IconBadge(
              glyph: paused ? AppGlyphs.block : AppGlyphs.checkCircle,
              color: color.withValues(alpha: 0.14),
              foregroundColor: color,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  Text(
                    title,
                    style: AppTextStyle.headline.of(context).copyWith(
                      color: scheme.onSurface,
                      fontFeatures: appTabularFigures,
                    ),
                  ),
                  Text(hint, style: context.listCaptionStyle),
                ],
              ),
            ),
            if (paused)
              TextButton(
                onPressed: busy ? null : onResume,
                child: Text(context.l10n.blockPauseResume),
              ),
          ],
        ),
      ),
    );
  }
}

/// The duration control as a grouped row: one tap anywhere opens the duration menu, and the picker
/// glyph on the right marks it as an opener rather than a preset button.
class _PauseDurationRow extends StatelessWidget {
  const _PauseDurationRow({
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
    return ListItem(
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
