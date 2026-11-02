part of 'tools_page.dart';

/// Shared input field wrapper for the panels. `FilledInputTheme` because a bare `TextField`
/// falls back to the outlined Material default, which clashes with the cards.
class _ToolField extends StatelessWidget {
  const _ToolField({
    required this.controller,
    required this.hintText,
    required this.glyph,
    this.onSubmitted,
    this.onChanged,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String hintText;
  final Glyph glyph;
  final ValueChanged<String>? onSubmitted;

  /// For fields that sync to the provider while typing (for example a persisted speed-test
  /// domain); fields read only on submit can omit it.
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return FilledInputTheme(
      child: TextField(
        controller: controller,
        enabled: enabled,
        autocorrect: false,
        textInputAction: TextInputAction.go,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: GlyphIcon(glyph),
        ),
      ),
    );
  }
}

/// Shared "via tunnel" switch row. Each tool has its own flag in `network_tools_settings` (keys
/// copied from the legacy `NetworkToolsSettingsStore`); off means the physical network is used.
class _ViaTunnelRow extends ConsumerWidget {
  const _ViaTunnelRow({
    required this.storageKey,
    required this.title,
    required this.subtitle,
    required this.value,
    this.enabled = true,
  });

  final String storageKey;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListItem.toggle(
      leading: const GlyphIcon(AppGlyphs.link, size: 20),
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: enabled
          ? (next) => setNetworkToolFlag(ref, storageKey, next)
          : null,
    );
  }
}

/// Shared notice bar for failures, fallback notes and input errors.
class _ToolNotice extends StatelessWidget {
  const _ToolNotice({
    required this.text,
    this.isError = false,
    this.glyph = AppGlyphs.info,
  });

  final String text;
  final bool isError;
  final Glyph glyph;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final color = isError ? colorScheme.error : colorScheme.warning;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: CommonCard(
        padding: const EdgeInsets.all(12),
        isError: isError,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            GlyphIcon(glyph, size: 18, color: color),
            Expanded(
              child: Text(
                text,
                style: context.listCaptionStyle.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolSection extends StatelessWidget {
  const _ToolSection({required this.rows, this.footer});

  final List<KeyValueRow> rows;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: CommonCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          ),
        ),
        if (footer case final footer?) ListFooter(text: footer),
      ],
    );
  }
}

/// Shared action row; [running] disables the button rather than hiding it.
class _RunButton extends StatelessWidget {
  const _RunButton({
    required this.glyph,
    required this.label,
    required this.runningLabel,
    required this.running,
    required this.onPressed,
  });

  final Glyph glyph;
  final String label;
  final String runningLabel;
  final bool running;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: TonalButton(
        glyph: glyph,
        label: running ? runningLabel : label,
        onPressed: running ? null : onPressed,
      ),
    );
  }
}

String _msText(double? value) =>
    value == null ? '—' : '${value.toStringAsFixed(1)} ms';
