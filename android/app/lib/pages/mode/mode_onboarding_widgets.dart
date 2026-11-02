part of 'mode_onboarding_page.dart';

/// Centered because the buttons are pinned to the bottom.
class _StepScaffold extends StatelessWidget {
  const _StepScaffold({
    required this.glyph,
    required this.title,
    required this.description,
    required this.children,
  });

  final Glyph glyph;
  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: IconBadge(
                    glyph: glyph,
                    size: 88,
                    glyphSize: 40,
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    foregroundColor: colorScheme.primary,
                    shape: AppShape.full,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTextStyle.pageTitle.of(context, emphasized: true),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 18),
                ...children,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({
    required this.glyph,
    required this.title,
    required this.detail,
  });

  final Glyph glyph;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CommonCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            GlyphIcon(glyph, size: 20, color: colorScheme.primary),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 3,
                children: [
                  Text(
                    title,
                    style: AppTextStyle.subheadline.of(
                      context,
                      emphasized: true,
                    ),
                  ),
                  Text(
                    detail,
                    style: AppTextStyle.caption1
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One permission row with its live state; tapping it asks the system, so the step is actionable
/// instead of a wall of text. A denied permission stays tappable: a second tap opens the settings
/// screen that can still change it.
class _PermissionRow extends ConsumerWidget {
  const _PermissionRow({
    required this.permission,
    required this.glyph,
    required this.name,
    required this.level,
    required this.detail,
  });

  final AppPermission permission;
  final Glyph glyph;
  final String name;
  final String level;
  final String detail;

  Future<void> _request(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(permissionStatesProvider.notifier);
    final snapshot = await notifier.request(permission);
    if (!context.mounted) {
      return;
    }
    if (snapshot.of(permission) == true) {
      return;
    }
    // A permanently denied permission only changes through the settings screen.
    final opened = await notifier.openSystemSettings(permission);
    if (!context.mounted || !opened) {
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(context.l10n.permStillDenied(name)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 2600),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final required = level == context.l10n.permRequired;
    final state = ref.watch(permissionStatesProvider).value?.of(permission);
    final granted = state == true;
    final statusLabel = switch (state) {
      true => context.l10n.permGranted,
      false => context.l10n.permDenied,
      null => context.l10n.permUnknown,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CommonCard(
        padding: const EdgeInsets.all(14),
        child: InkWell(
          onTap: granted ? null : () => _request(context, ref),
          borderRadius: AppRadius.md,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              IconBadge(
                glyph: granted ? AppGlyphs.checkCircle : glyph,
                size: 44,
                glyphSize: 22,
                color: granted
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHigh,
                foregroundColor: granted
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.primary,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    Row(
                      spacing: 6,
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: AppTextStyle.subheadline.of(
                              context,
                              emphasized: true,
                            ),
                          ),
                        ),
                        TonalChip(
                          label: level,
                          color: required
                              ? colorScheme.errorContainer
                              : colorScheme.secondaryContainer,
                          foregroundColor: required
                              ? colorScheme.onErrorContainer
                              : colorScheme.onSecondaryContainer,
                          onPressed: null,
                        ),
                        TonalChip(
                          label: statusLabel,
                          color: granted
                              ? colorScheme.secondaryContainer
                              : colorScheme.surfaceContainerHighest,
                          foregroundColor: granted
                              ? colorScheme.onSecondaryContainer
                              : colorScheme.onSurfaceVariant,
                          onPressed: null,
                        ),
                      ],
                    ),
                    Text(
                      detail,
                      style: AppTextStyle.caption1
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (!granted)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: TonalButton(
                    size: TonalButtonSize.bar,
                    label: context.l10n.permGrant,
                    onPressed: () => _request(context, ref),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
