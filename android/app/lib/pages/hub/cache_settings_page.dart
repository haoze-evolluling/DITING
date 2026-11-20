import 'package:flutter/services.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/vpn/cache_presets.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// DNS cache settings (upstream `CacheSettingsScreen`). The switch and presets write the
/// nine legacy `dns_cache_*_v2` keys directly, because the engine follows that policy.
///
/// Besides the three stored presets the page offers a custom policy: it writes the same keys,
/// keeps `dns_cache_preset_v3` at `custom`, and lets each duration be edited on its own.
class CacheSettingsPage extends ConsumerWidget {
  const CacheSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(legacySettingsProvider);
    final enabled = settings.cacheEnabled;
    final preset = DnsCachePreset.current(settings);
    final l10n = context.l10n;
    return CommonScaffold(
      title: l10n.cacheSettingsTitle,
      body: PageBody(
        children: [
          generateSection(
            title: l10n.cacheSection,
            items: [
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.database),
                title: Text(l10n.cacheLocalDns),
                subtitle: Text(
                  enabled
                      ? cachePolicySummary(settings, l10n)
                      : l10n.cacheOffNote,
                ),
                value: enabled,
                onChanged: (value) {
                  preset.applyTo(settings, enabled: value);
                  ref.read(legacySettingsRevisionProvider.notifier).bump();
                },
              ),
            ],
          ),
          if (enabled)
            generateSection(
              title: l10n.cachePresetSection,
              items: [
                ListItem<DnsCachePreset>.options(
                  leading: const GlyphIcon(AppGlyphs.database),
                  title: Text(l10n.cachePresetSection),
                  subtitle: Text(
                    '${preset.summary(l10n)}。${preset.description(l10n)}',
                  ),
                  value: preset,
                  options: DnsCachePreset.values,
                  textBuilder: (option) => option.label(l10n),
                  onChanged: (option) {
                    option.applyTo(settings, enabled: enabled);
                    ref.read(legacySettingsRevisionProvider.notifier).bump();
                  },
                ),
              ],
              footer: l10n.cachePresetNote,
            ),
          if (enabled && preset == DnsCachePreset.custom)
            _CustomCacheSection(settings: settings, enabled: enabled),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// The parameter rows behind the custom preset. Every edit writes the nine keys immediately, so
/// leaving the page cannot lose a value.
class _CustomCacheSection extends ConsumerWidget {
  const _CustomCacheSection({required this.settings, required this.enabled});

  final LegacySettings settings;
  final bool enabled;

  void _save(WidgetRef ref, DnsCacheCustomPolicy policy) {
    policy.write(settings, enabled: enabled);
    ref.read(legacySettingsRevisionProvider.notifier).bump();
  }

  Future<void> _editSeconds(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required int value,
    required DnsCacheCustomPolicy Function(DnsCacheCustomPolicy, int) apply,
  }) async {
    final seconds = await showFloatingDialog<int>(
      context: context,
      child: _SecondsDialog(title: title, initialValue: value),
    );
    if (seconds == null) return;
    _save(ref, apply(DnsCacheCustomPolicy.read(settings), seconds));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final policy = DnsCacheCustomPolicy.read(settings);
    final limitMode = policy.mode == DnsCacheCustomPolicy.modeLimitMax;
    final fixedMode = policy.mode == DnsCacheCustomPolicy.modeFixed;
    return generateSection(
      title: l10n.cacheCustomSection,
      items: [
        _ModeRow(
          mode: policy.mode,
          onChanged: (mode) => _save(ref, policy.copyWith(mode: mode)),
        ),
        if (limitMode)
          _SecondsRow(
            glyph: AppGlyphs.clock,
            title: l10n.cacheCustomMaxTtl,
            value: policy.maxTtlSeconds,
            onTap: () => _editSeconds(
              context,
              ref,
              title: l10n.cacheCustomMaxTtl,
              value: policy.maxTtlSeconds,
              apply: (current, seconds) =>
                  current.copyWith(maxTtlSeconds: seconds),
            ),
          ),
        if (fixedMode)
          _SecondsRow(
            glyph: AppGlyphs.clock,
            title: l10n.cacheCustomFixedTtl,
            value: policy.fixedTtlSeconds,
            onTap: () => _editSeconds(
              context,
              ref,
              title: l10n.cacheCustomFixedTtl,
              value: policy.fixedTtlSeconds,
              apply: (current, seconds) =>
                  current.copyWith(fixedTtlSeconds: seconds),
            ),
          ),
        ListItem.toggle(
          leading: const GlyphIcon(AppGlyphs.speed, size: 20),
          title: Text(l10n.cacheCustomMinTtlEnabled),
          subtitle: Text(l10n.cacheCustomMinTtlEnabledDesc),
          value: policy.minTtlEnabled,
          onChanged: (value) =>
              _save(ref, policy.copyWith(minTtlEnabled: value)),
        ),
        if (policy.minTtlEnabled)
          _SecondsRow(
            glyph: AppGlyphs.speed,
            title: l10n.cacheCustomMinTtl,
            value: policy.minTtlSeconds,
            onTap: () => _editSeconds(
              context,
              ref,
              title: l10n.cacheCustomMinTtl,
              value: policy.minTtlSeconds,
              apply: (current, seconds) =>
                  current.copyWith(minTtlSeconds: seconds),
            ),
          ),
        ListItem.toggle(
          leading: const GlyphIcon(AppGlyphs.sync, size: 20),
          title: Text(l10n.cacheCustomStaleEnabled),
          subtitle: Text(l10n.cacheCustomStaleEnabledDesc),
          value: policy.staleFallbackEnabled,
          onChanged: (value) =>
              _save(ref, policy.copyWith(staleFallbackEnabled: value)),
        ),
        if (policy.staleFallbackEnabled)
          _SecondsRow(
            glyph: AppGlyphs.sync,
            title: l10n.cacheCustomStaleSeconds,
            value: policy.staleFallbackSeconds,
            onTap: () => _editSeconds(
              context,
              ref,
              title: l10n.cacheCustomStaleSeconds,
              value: policy.staleFallbackSeconds,
              apply: (current, seconds) =>
                  current.copyWith(staleFallbackSeconds: seconds),
            ),
          ),
      ],
      footer: l10n.cacheCustomFooter,
    );
  }
}

/// The TTL mode picker; the label of the current mode doubles as the button.
class _ModeRow extends StatelessWidget {
  const _ModeRow({required this.mode, required this.onChanged});

  final String mode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    PopupOpen? openMenu;
    return ListItem(
      leading: const GlyphIcon(AppGlyphs.sliders, size: 20),
      title: Text(l10n.cacheCustomMode),
      subtitle: Text(cacheCustomModeDescription(l10n, mode)),
      onTap: () => openMenu?.call(),
      trailing: CommonPopupBox(
        targetBuilder: (open) {
          openMenu = open;
          return _ValueButton(
            label: cacheCustomModeLabel(l10n, mode),
            glyph: AppGlyphs.picker,
            onPressed: open,
          );
        },
        popupBuilder: (_) => CommonPopupMenu(
          items: [
            for (final option in DnsCacheCustomPolicy.modes)
              CommonPopupMenuItem(
                label: cacheCustomModeLabel(l10n, option),
                checked: option == mode,
                onPressed: () => onChanged(option),
              ),
          ],
        ),
      ),
    );
  }
}

class _SecondsRow extends StatelessWidget {
  const _SecondsRow({
    required this.glyph,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final Glyph glyph;
  final String title;
  final int value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListItem(
      leading: GlyphIcon(glyph, size: 20),
      title: Text(title),
      onTap: onTap,
      trailing: _ValueButton(
        label: formatCacheSeconds(context.l10n, value),
        onPressed: onTap,
      ),
    );
  }
}

class _ValueButton extends StatelessWidget {
  const _ValueButton({
    required this.label,
    required this.onPressed,
    this.glyph = AppGlyphs.edit,
  });

  final String label;
  final VoidCallback onPressed;
  final Glyph glyph;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: context.colorScheme.onSurfaceVariant,
        textStyle: AppTextRole.rowTitle.of(context),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [Text(label), GlyphIcon(glyph, size: 16)],
      ),
    );
  }
}

/// A whole-second editor. The engine clamps every duration to 30–86400 s, so the dialog rejects
/// anything outside that window instead of silently trimming it.
class _SecondsDialog extends StatefulWidget {
  const _SecondsDialog({required this.title, required this.initialValue});

  final String title;
  final int initialValue;

  @override
  State<_SecondsDialog> createState() => _SecondsDialogState();
}

class _SecondsDialogState extends State<_SecondsDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.initialValue}');
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_controller.text.trim());
    if (value == null ||
        value < DnsCacheCustomPolicy.minSeconds ||
        value > DnsCacheCustomPolicy.maxSeconds) {
      setState(() => _error = context.l10n.cacheCustomSecondsInvalid);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CommonDialog(
      title: widget.title,
      hasFields: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.uiCancel),
        ),
        TextButton(onPressed: _submit, child: Text(l10n.commonSave)),
      ],
      child: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: l10n.cacheCustomSecondsLabel,
          helperText: l10n.cacheCustomSecondsHelper,
          errorText: _error,
        ),
      ),
    );
  }
}
