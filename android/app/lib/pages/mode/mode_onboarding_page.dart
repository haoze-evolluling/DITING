import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/native/permissions_bridge.dart';
import 'package:diting_android/router.dart';
import 'package:diting_android/state/permission_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/icon_badge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

part 'mode_onboarding_widgets.dart';
part 'mode_onboarding_steps.dart';

/// Three-step onboarding: choose mode, request permissions, key tips. Step 2 both explains each
/// permission and opens the real system dialog, because a page that only describes them leaves the
/// service unprotected: without POST_NOTIFICATIONS the foreground notification is dropped, and
/// without the VPN consent the tunnel cannot start at all.
class ModeOnboardingPage extends ConsumerStatefulWidget {
  const ModeOnboardingPage({super.key});

  @override
  ConsumerState<ModeOnboardingPage> createState() => _ModeOnboardingPageState();
}

class _ModeOnboardingPageState extends ConsumerState<ModeOnboardingPage> {
  static const _steps = 3;

  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _goTo(int index) async {
    if (index < 0 || index >= _steps) {
      return;
    }
    await _controller.animateToPage(
      index,
      duration: commonDuration,
      curve: Curves.easeOutCubic,
    );
  }

  /// Finish onboarding: write the flag and return home. go(Routes.home) rather than pop,
  /// because this page is reached both by pushReplacement and by push.
  void _finish() {
    ref.read(onboardingProvider.notifier).complete();
    ref.read(workModeSelectedProvider.notifier).markSelected();
    context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(workModeProvider);
    final last = _index == _steps - 1;
    return CommonScaffold(
      title: context.l10n.onboardingTitle,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.close,
          tooltip: context.l10n.onboardingSkip,
          onPressed: () {
            ref.read(onboardingProvider.notifier).complete();
            context.go(Routes.home);
          },
        ),
      ],
      // The app bar floats over the body (extendBodyBehindAppBar) and this page uses a bare Column,
      // so
      // without this clearance the progress bar and hero icon would be drawn under the status bar.
      body: AppBarClearance(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StepIndicator(steps: _steps, current: _index),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (index) => setState(() => _index = index),
                children: [
                  _ChooseModeStep(mode: mode),
                  const _PermissionStep(),
                  _FinishStep(mode: mode),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                spacing: 10,
                children: [
                  if (_index > 0)
                    Expanded(
                      child: TonalButton(
                        size: TonalButtonSize.bar,
                        glyph: AppGlyphs.chevronBack,
                        label: context.l10n.onboardingPrev,
                        onPressed: () => _goTo(_index - 1),
                      ),
                    ),
                  Expanded(
                    flex: 2,
                    child: TonalButton(
                      size: TonalButtonSize.bar,
                      glyph: last ? AppGlyphs.check : AppGlyphs.chevronForward,
                      label: last ? context.l10n.onboardingStart : context.l10n.onboardingNext,
                      onPressed: last ? _finish : () => _goTo(_index + 1),
                    ),
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

/// Three-segment progress bar: passed 40% opaque, current primary, pending surface.
class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.steps, required this.current});

  final int steps;
  final int current;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Row(
        spacing: 6,
        children: [
          for (var index = 0; index < steps; index++)
            Expanded(
              child: AnimatedContainer(
                duration: midDuration,
                curve: Curves.easeOut,
                height: 4,
                decoration: ShapeDecoration(
                  shape: AppShape.full,
                  color: index == current
                      ? colorScheme.primary
                      : index < current
                      ? colorScheme.primary.withValues(alpha: 0.4)
                      : colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
