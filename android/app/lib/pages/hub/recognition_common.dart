library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/recognition/recognition_members.dart';
import 'package:diting_android/state/recognition_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/widgets/empty_state.dart';
import 'package:diting_android/widgets/rainbow_avatar_frame.dart';
import 'package:diting_android/widgets/status_pill.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class RecognitionAvatar extends ConsumerWidget {
  const RecognitionAvatar({super.key, required this.member, this.size = 48});

  final RecognitionMember member;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (member.frame == null) return _circle(context, ref, size);
    return RainbowAvatarFrame(
      size: size,
      child: _circle(context, ref, size - rainbowAvatarPadding * 2),
    );
  }

  Widget _circle(BuildContext context, WidgetRef ref, double diameter) {
    final fileName = member.avatarFileName;
    if (fileName == null) {
      return _frame(context, _placeholder(context), diameter);
    }
    final bytes = ref.watch(recognitionAvatarProvider(fileName)).value;
    if (bytes == null) {
      return _frame(context, _placeholder(context), diameter);
    }
    return _frame(
      context,
      Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _placeholder(context),
      ),
      diameter,
    );
  }

  Widget _placeholder(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final dimension = constraints.biggest.shortestSide;
      return Center(
        child: GlyphIcon(
          AppGlyphs.account,
          size: dimension * 0.55,
          color: context.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
        ),
      );
    },
  );

  Widget _frame(BuildContext context, Widget child, double diameter) {
    return Container(
      width: diameter,
      height: diameter,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.colorScheme.surfaceContainerHigh,
      ),
      child: child,
    );
  }
}

class RecognitionMemberRow extends StatelessWidget {
  const RecognitionMemberRow({super.key, required this.member});

  final RecognitionMember member;

  @override
  Widget build(BuildContext context) {
    return ListItem(
      leading: RecognitionAvatar(member: member),
      title: Row(
        children: [
          Flexible(
            child: Text(
              member.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (member.count > 1) ...[
            const SizedBox(width: 8),
            _SponsorCountBadge(count: member.count),
          ],
        ],
      ),
    );
  }
}

class _SponsorCountBadge extends StatelessWidget {
  const _SponsorCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return StatusPill(
      label: '× $count',
      color: context.colorScheme.primary,
      alpha: 0.12,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      style: AppTextRole.micro,
      tabular: true,
    );
  }
}

class RecognitionListPage extends ConsumerStatefulWidget {
  const RecognitionListPage({
    super.key,
    required this.title,
    required this.intro,
    required this.sectionTitle,
    required this.select,
    this.sortable = false,
  });

  final String title;
  final String intro;
  final String sectionTitle;

  final List<RecognitionMember> Function(RecognitionMembers) select;

  final bool sortable;

  @override
  ConsumerState<RecognitionListPage> createState() =>
      _RecognitionListPageState();
}

class _RecognitionListPageState extends ConsumerState<RecognitionListPage> {
  bool _newestFirst = false;
  bool _requestedFirstLoad = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureFresh());
  }

  void _ensureFresh() {
    if (!mounted) return;
    if (ref.read(recognitionMembersProvider).value == null) return;
    _requestedFirstLoad = true;
    ref.read(recognitionMembersProvider.notifier).ensureFresh();
  }

  Future<void> _refresh() async {
    await ref.read(recognitionMembersProvider.notifier).refresh();
    if (!mounted) return;
    final state = ref.read(recognitionMembersProvider).value;
    showAppSnack(
      context,
      state?.error ?? context.l10n.recognitionUpdated,
      duration: const Duration(milliseconds: 2000),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(recognitionMembersProvider);
    final data = async.value;
    final state = data ?? const RecognitionState();
    if (!_requestedFirstLoad && data != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureFresh());
    }
    final members = state.members;
    final listed = members == null
        ? const <RecognitionMember>[]
        : widget.select(members);
    final visible = widget.sortable && _newestFirst
        ? listed.reversed.toList(growable: false)
        : listed;

    return CommonScaffold(
      title: widget.title,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.refresh,
          tooltip: context.l10n.recognitionRefresh,
          isLoading: state.isRefreshing,
          onPressed: _refresh,
        ),
        if (widget.sortable)
          IconButtonData(
            glyph: AppGlyphs.sort,
            tooltip: _newestFirst
                ? context.l10n.recognitionSortAsc
                : context.l10n.recognitionSortDesc,
            isSelected: _newestFirst,
            onPressed: () => setState(() => _newestFirst = !_newestFirst),
          ),
      ],
      body: PageBody(
        children: [
          if (!state.hasMembers && (state.isRefreshing || data == null))
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 64),
              child: Center(child: CommonCircleLoading()),
            )
          else if (!state.hasMembers)
            EmptyStateBox(
              minHeight: 320,
              child: NullStatus(
                label: state.error == null
                    ? context.l10n.recognitionEmpty
                    : context.l10n.recognitionLoadFailed,
                description: state.error ?? context.l10n.recognitionEmptyBody,
                illustration: state.error == null
                    ? NullStatusIllustration.data
                    : NullStatusIllustration.error,
                action: TextButton(
                  onPressed: _refresh,
                  child: Text(
                    state.error == null
                        ? context.l10n.recognitionLoad
                        : context.l10n.recognitionRetry,
                  ),
                ),
              ),
            )
          else if (visible.isEmpty)
            EmptyStateBox(
              minHeight: 280,
              child: NullStatus(
                label: context.l10n.recognitionNoMembers,
                description: context.l10n.recognitionNoMembersBody,
                illustration: NullStatusIllustration.data,
                action: TextButton(
                  onPressed: _refresh,
                  child: Text(context.l10n.recognitionRefreshShort),
                ),
              ),
            )
          else
            generateSection(
              title: '${widget.sectionTitle}（${visible.length}）',
              items: [
                for (final member in visible)
                  RecognitionMemberRow(member: member),
              ],
            ),
          if (state.hasMembers) _StatusFooter(state: state),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _StatusFooter extends StatelessWidget {
  const _StatusFooter({required this.state});

  final RecognitionState state;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (state.error != null) {
      parts.add(state.error!);
    } else if (state.fromCache) {
      parts.add(context.l10n.recognitionCached);
    }
    final updatedAt = state.updatedAt;
    if (updatedAt != null) {
      parts.add(context.l10n.recognitionLastUpdate(_formatTime(updatedAt)));
    }
    if (parts.isEmpty) {
      parts.add(context.l10n.recognitionCloudNote);
    }
    return ListFooter(text: parts.join(' · '));
  }

  static String _formatTime(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
