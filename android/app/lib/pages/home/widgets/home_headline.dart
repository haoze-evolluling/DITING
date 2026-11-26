import 'package:diting_android/data/vpn/power_state.dart';
import 'package:diting_android/widgets/dashboard/dashboard_density.dart';
import 'package:diting_android/pages/home/widgets/home_power_button.dart';
import 'package:diting_android/state/appearance_providers.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

List<Widget> buildHomeHeadline({
  required BuildContext context,
  required WidgetRef ref,
  required PowerState state,
  required VoidCallback onPressed,
  EdgeInsets padding = const EdgeInsets.fromLTRB(32, 20, 32, 4),
}) {
  final opacity = ref.watch(homeOpacityProvider);
  final sentence = ref.watch(homeSentenceProvider);
  final text = state.isRunning || state == PowerState.starting
      ? sentence.running
      : sentence.stopped;
  final scale = DashboardDensityScope.scaleOf(context);
  return [
    SizedBox(height: 8 * scale),
    Opacity(
      opacity: opacity[HomeLayer.powerButton] ?? 1,
      child: HomePowerButton(state: state, onPressed: onPressed),
    ),
    if (text.isNotEmpty)
      Opacity(
        opacity: opacity[HomeLayer.poem] ?? 1,
        child: Padding(
          padding: padding,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: AppTextRole.body
                .of(context)
                .copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    const SizedBox(height: 16),
  ];
}
