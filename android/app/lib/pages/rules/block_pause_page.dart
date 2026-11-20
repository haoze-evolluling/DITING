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

const _presetMinutes = <int>[15, 30, 60];

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

  int _selectedMinutes = _presetMinutes.first;

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

  Future<void> _run(
    Future<BlockPauseState> Function(BlockPauseBridge) action,
  ) async {
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

  Future<void> _pause(int minutes) {
    setState(() => _selectedMinutes = minutes);
    return _run((bridge) => bridge.pause(minutes));
  }

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
          PageIntroText(text: l10n.blockPauseIntro),
          _StatusHero(
            paused: paused,
            remaining: state?.remaining ?? Duration.zero,
            busy: _busy,
            onResume: () => _run((bridge) => bridge.clear()),
          ),
          generateSection(
            title: l10n.blockPauseControlSectionTitle,
            items: [
              _PauseDurationRow(
                busy: _busy,
                selectedMinutes: _selectedMinutes,
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
                    : (value) =>
                          _run((bridge) => bridge.setAllowlistOnly(value)),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                _error!,
                style: AppTextRole.body
                    .of(context)
                    .copyWith(color: context.colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

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
              glyph: paused ? AppGlyphs.pause : AppGlyphs.checkCircle,
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
                    style: AppTextRole.cardTitle
                        .of(context)
                        .copyWith(
                          color: scheme.onSurface,
                          fontFeatures: appTabularFigures,
                        ),
                  ),
                  Text(hint, style: AppTextRole.supportingText.of(context)),
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

class _PauseDurationRow extends StatelessWidget {
  const _PauseDurationRow({
    required this.busy,
    required this.selectedMinutes,
    required this.onPause,
    required this.onCustom,
  });

  final bool busy;
  final int selectedMinutes;
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
              textStyle: AppTextRole.rowTitle.of(context),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                Text(l10n.blockPauseMinutesValue(selectedMinutes)),
                const GlyphIcon(AppGlyphs.picker),
              ],
            ),
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
              section: const CommonPopupMenuSection(),
              onPressed: busy ? null : onCustom,
            ),
          ],
        ),
      ),
    );
  }
}

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
        TextButton(onPressed: _submit, child: Text(context.l10n.commonSave)),
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

String _formatRemaining(Duration remaining) {
  String two(int value) => value.toString().padLeft(2, '0');
  final hours = remaining.inHours;
  final minutes = remaining.inMinutes % 60;
  final seconds = remaining.inSeconds % 60;
  return hours > 0
      ? '$hours:${two(minutes)}:${two(seconds)}'
      : '$minutes:${two(seconds)}';
}
