part of 'tools_page.dart';

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
  final IconData glyph;
  final ValueChanged<String>? onSubmitted;

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
          prefixIcon: Icon(glyph),
        ),
      ),
    );
  }
}

class _ToolInputCard extends StatelessWidget {
  const _ToolInputCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: CommonCard(padding: const EdgeInsets.all(12), child: child),
    );
  }
}

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
      leading: const Icon(TablerIcons.link, size: 20),
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: enabled
          ? (next) => setNetworkToolFlag(ref, storageKey, next)
          : null,
    );
  }
}

class _ToolNotice extends StatelessWidget {
  const _ToolNotice({
    required this.text,
    this.isError = false,
    this.glyph = TablerIcons.info_circle,
  });

  final String text;
  final bool isError;
  final IconData glyph;

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
            Icon(glyph, size: 18, color: color),
            Expanded(
              child: Text(
                text,
                style: AppTextRole.supportingText
                    .of(context)
                    .copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolSection extends StatelessWidget {
  const _ToolSection({this.title, required this.rows, this.footer});

  final String? title;
  final List<KeyValueRow> rows;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title case final title?) ListHeader(title: title),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
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

class _RunButton extends StatelessWidget {
  const _RunButton({
    required this.glyph,
    required this.label,
    required this.runningLabel,
    required this.running,
    required this.onPressed,
  });

  final IconData glyph;
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
        size: TonalButtonSize.section,
        onPressed: running ? null : onPressed,
      ),
    );
  }
}

class _ToolEmptyCard extends StatelessWidget {
  const _ToolEmptyCard({
    required this.glyph,
    required this.title,
    required this.body,
  });

  final IconData glyph;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: CommonCard(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          children: [
            Icon(glyph, size: 28, color: colorScheme.primary),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextRole.bodyStrong
                  .of(context)
                  .copyWith(color: colorScheme.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              textAlign: TextAlign.center,
              style: AppTextRole.supportingText.of(context),
            ),
          ],
        ),
      ),
    );
  }
}

String _msText(double? value) =>
    value == null ? '—' : '${value.toStringAsFixed(1)} ms';
