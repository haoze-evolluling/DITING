library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/fonts/font_repository.dart';
import 'package:diting_android/routes/system_routes.dart';
import 'package:diting_shared/state/appearance_extra_providers.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_android/state/font_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/widgets/nav_entry_row.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class FontFamilyPage extends ConsumerStatefulWidget {
  const FontFamilyPage({super.key});

  @override
  ConsumerState<FontFamilyPage> createState() => _FontFamilyPageState();
}

class _FontFamilyPageState extends ConsumerState<FontFamilyPage> {
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedFontFamilyProvider);
    final scale = ref.watch(textScaleProvider);
    final fonts = ref.watch(importedFontsProvider);
    return CommonScaffold(
      title: context.l10n.fontFamilyTitle,
      body: PageBody(
        dockSpacer: false,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: CommonCard(
              padding: EdgeInsets.zero,
              child: NavEntryRow(
                glyph: AppGlyphs.textSize,
                title: context.l10n.appearanceFontSizeLabel,
                subtitle: context.l10n.appearanceFontSizeCurrent(
                  (scale * 100).round(),
                ),
                onPressed: () => context.push(SystemPaths.fontSize),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _PreviewHero(
              family: selected,
              label: fontLabelOf(fonts, selected),
            ),
          ),
          const SizedBox(height: 12),
          generateSection(
            title: context.l10n.appearanceFontSection,
            items: [
              _FontRow(
                label: context.l10n.fontSystemDefault,
                description: context.l10n.fontFamilySystemDefault,
                family: null,
                selected: selected == null,
                onTap: () => _select(null),
              ),
              for (final font in fonts)
                _FontRow(
                  label: font.label,
                  description: context.l10n.fontFamilyImported,
                  family: font.family,
                  selected: selected == font.family,
                  onTap: () => _select(font.family),
                  onDelete: () => _delete(font),
                ),
            ],
            footer: fonts.isEmpty
                ? context.l10n.fontFamilyEmpty
                : context.l10n.fontFamilyFooter,
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _ImportCard(
              isImporting: _importing,
              onPressed: _importing ? null : _import,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              context.l10n.fontFamilyLocalOnly,
              style: AppTextRole.supportingText.of(context),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _select(String? family) {
    ref.read(selectedFontFamilyProvider.notifier).select(family);
  }

  Future<void> _import() async {
    setState(() => _importing = true);
    final result = await ref.read(fontRepositoryProvider).import();
    if (!mounted) {
      return;
    }
    setState(() => _importing = false);
    if (result.cancelled) {
      return;
    }
    final font = result.font;
    if (font == null) {
      showAppSnack(
        context,
        result.error ?? context.l10n.fontFamilyImportFailed,
        duration: const Duration(milliseconds: 1800),
      );
      return;
    }
    ref.invalidate(importedFontsProvider);
    _select(font.family);
    showAppSnack(
      context,
      context.l10n.appearanceFontImported(font.label),
      duration: const Duration(milliseconds: 1800),
    );
  }

  Future<void> _delete(ImportedFont font) async {
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.fontFamilyDeleteTitle,
        destructive: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.commonDelete),
          ),
        ],
        child: Text(context.l10n.fontFamilyDeleteConfirm(font.label)),
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    if (ref.read(selectedFontFamilyProvider) == font.family) {
      _select(null);
    }
    await ref.read(fontRepositoryProvider).delete(font);
    if (!mounted) {
      return;
    }
    ref.invalidate(importedFontsProvider);
    showAppSnack(
      context,
      context.l10n.appearanceFontDeleted(font.label),
      duration: const Duration(milliseconds: 1800),
    );
  }
}

class _PreviewHero extends StatelessWidget {
  const _PreviewHero({required this.family, required this.label});

  final String? family;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return CommonCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.appearancePoem,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextRole.sectionTitle
                .of(context)
                .copyWith(fontFamily: family),
          ),
          const SizedBox(height: 6),
          Text(
            'The quick brown fox jumps over the lazy dog · 0123456789',
            style: AppTextRole.supportingText
                .of(context)
                .copyWith(
                  fontFamily: family,
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 10),
          MetaChip(label: label),
        ],
      ),
    );
  }
}

class _FontRow extends StatelessWidget {
  const _FontRow({
    required this.label,
    required this.description,
    required this.family,
    required this.selected,
    required this.onTap,
    this.onDelete,
  });

  final String label;
  final String description;
  final String? family;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return DecorationListItem(
      isSelected: selected,
      onPressed: onTap,
      leading: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          shape: AppShape.standard,
          color: context.raisedSurfaceLevel.colorOf(colorScheme),
        ),
        child: Text(
          'Aa',
          style: AppTextRole.bodyStrong
              .of(context)
              .copyWith(
                fontFamily: family,
                color: colorScheme.onSurfaceVariant,
              ),
        ),
      ),
      title: Text(
        label,
        style: AppTextRole.rowTitle.of(context).copyWith(fontFamily: family),
      ),
      subtitle: Text(description),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onDelete case final onDelete?)
            IconButton(
              tooltip: context.l10n.commonDelete,
              onPressed: onDelete,
              icon: const GlyphIcon(AppGlyphs.delete, size: 20),
            ),
          if (selected) const SelectionCheck() else const SizedBox(width: 24),
        ],
      ),
    );
  }
}

class _ImportCard extends StatelessWidget {
  const _ImportCard({required this.isImporting, required this.onPressed});

  final bool isImporting;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return CommonCard(
      onPressed: onPressed,
      inert: onPressed == null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          GlyphIcon(
            AppGlyphs.importFile,
            size: commonCardIconSize,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.fontFamilyImport,
                  style: AppTextRole.rowTitle.of(context),
                ),
                const SizedBox(height: 2),
                Text(
                  isImporting
                      ? context.l10n.fontFamilyReading
                      : context.l10n.fontFamilyPickFile,
                  style: AppTextRole.supportingText.of(context),
                ),
              ],
            ),
          ),
          if (isImporting)
            const CommonCircleLoading(size: 20)
          else
            const GlyphIcon(AppGlyphs.chevronForward, size: 20),
        ],
      ),
    );
  }
}
