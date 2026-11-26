import 'package:diting_android/widgets/dashboard/dashboard_style.dart';
import 'package:diting_android/routes/routes.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/icon_badge.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:diting_android/widgets/status_pill.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

part 'dashboard_detail_stats.dart';

class DashboardDetailScaffold extends StatelessWidget {
  const DashboardDetailScaffold({
    super.key,
    required this.title,
    this.actions = const [],
    required this.children,
  });

  final String title;
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: title,
      backAction: () => _back(context),
      actions: actions.isEmpty ? null : actions,
      body: PageBody(
        padding: const EdgeInsets.only(top: 4),
        children: children,
      ),
    );
  }

  static void _back(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router != null && router.canPop()) {
      router.pop();
      return;
    }
    final navigator = Navigator.maybeOf(context);
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return;
    }
    if (router != null) {
      router.go(DashboardPaths.dashboard);
    }
  }
}

class DashboardDetailCard extends StatelessWidget {
  const DashboardDetailCard({
    super.key,
    this.glyph,
    this.title,
    this.trailing = const [],
    this.footer,
    this.semanticLabel,
    this.onTap,
    this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 16),
    required this.child,
  });

  final IconData? glyph;
  final String? title;
  final List<Widget> trailing;
  final String? footer;
  final String? semanticLabel;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shape = AppShape.standard;
    final content = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title case final title?) ...[
            _Header(glyph: glyph, title: title, trailing: trailing),
            const SizedBox(height: 14),
          ],
          child,
          if (footer case final footer?) ...[
            const SizedBox(height: 12),
            Text(footer, style: _captionStyle(context)),
          ],
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Semantics(
        container: true,
        label: semanticLabel,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: ShapeDecoration(
            color: DashboardColors.of(context).card,
            shape: shape,
            shadows: DashboardShadows.e1(context),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: onTap == null
                ? content
                : InkWell(customBorder: shape, onTap: onTap, child: content),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.glyph, required this.title, required this.trailing});

  final IconData? glyph;
  final String title;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Row(
      spacing: 8,
      children: [
        if (glyph case final glyph?)
          Icon(glyph, size: 18, color: colorScheme.onSurfaceVariant),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextRole.bodyStrong.of(context),
          ),
        ),
        ...trailing,
      ],
    );
  }
}

class DashboardDetailHero extends StatelessWidget {
  const DashboardDetailHero({
    super.key,
    required this.glyph,
    required this.label,
    required this.value,
    this.unit,
    this.hint,
    this.color,
    this.chipLabel,
    this.chipColor,
    this.tabular = false,
  });

  final IconData glyph;
  final String label;
  final String value;
  final String? unit;
  final String? hint;
  final Color? color;

  final String? chipLabel;
  final Color? chipColor;

  final bool tabular;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final colors = DashboardColors.of(context);
    final accent = color ?? colorScheme.primary;
    final hint = this.hint;
    final figure = color ?? colorScheme.onSurface;
    return DashboardDetailCard(
      semanticLabel: '$label $value',
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            spacing: 14,
            children: [
              IconBadge(
                glyph: glyph,
                size: 44,
                glyphSize: 22,
                color: colors.tone,
                foregroundColor: accent,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  spacing: 2,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _captionStyle(context),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: value,
                            style:
                                DashboardText.figure(
                                  context,
                                  AppTextRole.metricMedium,
                                  color: figure,
                                ).copyWith(
                                  fontFeatures: tabular
                                      ? appTabularFigures
                                      : null,
                                ),
                          ),
                          if (unit case final unit?)
                            TextSpan(
                              text: '  $unit',
                              style: DashboardText.unit(context),
                            ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (chipLabel case final chipLabel?)
                StatusPill(
                  label: chipLabel,
                  color: chipColor ?? colorScheme.onSurfaceVariant,
                  alpha: 0.12,
                ),
            ],
          ),
          if (hint != null && hint.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(hint, style: _captionStyle(context)),
          ],
        ],
      ),
    );
  }
}

TextStyle _captionStyle(BuildContext context) => AppTextRole.caption
    .of(context)
    .copyWith(color: context.colorScheme.onSurfaceVariant);
