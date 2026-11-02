// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:diting_shared/ui/context.dart';
import 'package:diting_shared/ui/fade_box.dart';
import 'package:diting_shared/ui/icons/icons.dart';
import 'package:diting_shared/ui/inherited.dart';
import 'package:diting_shared/ui/l10n.dart';
import 'package:diting_shared/ui/metrics.dart';
import 'package:diting_shared/ui/navigator.dart';
import 'package:diting_shared/ui/typography.dart';
// The shape names below come from material_new_shapes (which still owns `Morph` and
// `toPath`); hide material_ui's built-in copies so the import stays unambiguous.
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:material_ui/material_ui.dart'
    hide CornerRounding, MaterialShapes, RoundedPolygon;
part 'null_status_a.dart';

enum NullStatusIllustration {
  data,
  logs,
  proxies,
  profile,
  scripts,
  rules,
  connections,
  requests,
  dns,
  ntp,
  sniffer,
  tun,
  wifi,
  apps,
  icons,
  fonts,
  permission,
  camera,
  error,
  search,
}

class NullStatusSwitcher extends StatefulWidget {
  final bool isLoading;
  final bool isEmpty;
  final bool isSearching;

  final NullStatus? loadingStatus;
  final NullStatus? nullStatus;
  final Widget child;

  const NullStatusSwitcher({
    super.key,
    this.isLoading = false,
    this.isEmpty = false,
    this.isSearching = false,
    this.loadingStatus,
    this.nullStatus,
    required this.child,
  }) : assert(!isEmpty || nullStatus != null);

  @override
  State<NullStatusSwitcher> createState() => _NullStatusSwitcherState();
}

class _NullStatusSwitcherState extends State<NullStatusSwitcher> {
  static const _exitDuration = Duration(milliseconds: 150);
  static const _loadingStatusDelay = Duration(milliseconds: 400);

  late bool _loaded = !widget.isLoading;
  Timer? _loadingStatusTimer;
  var _showsLoadingStatus = false;

  @override
  void initState() {
    super.initState();
    if (!_loaded && widget.loadingStatus != null) {
      _loadingStatusTimer = Timer(
        _loadingStatusDelay,
        () => setState(() => _showsLoadingStatus = true),
      );
    }
  }

  @override
  void didUpdateWidget(covariant NullStatusSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loaded = _loaded || !widget.isLoading;
    if (_loaded) {
      _loadingStatusTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _loadingStatusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded && !_showsLoadingStatus) {
      return const SizedBox.expand();
    }
    final slot = switch ((widget.isEmpty, widget.isSearching)) {
      _ when !_loaded => _NullStatusSlot.loading,
      (true, true) => _NullStatusSlot.noResults,
      (true, false) => _NullStatusSlot.empty,
      (false, _) => _NullStatusSlot.content,
    };
    return AnimatedSwitcher(
      duration: context.motionDuration(commonDuration),
      reverseDuration: context.motionDuration(_exitDuration),
      switchInCurve: Easing.emphasizedDecelerate,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (currentChild, previousChildren) => LayoutBuilder(
        builder: (context, constraints) => Align(
          alignment: Alignment.center,
          child: Stack(
            alignment: Alignment.center,
            // Fill only with a bounded height: `StackFit.expand` forces infinite height otherwise.
            fit: constraints.hasBoundedHeight
                ? StackFit.expand
                : StackFit.loose,
            children: <Widget>[...previousChildren, ?currentChild],
          ),
        ),
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: animation.drive(Tween(begin: 0.92, end: 1.0)),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(slot),
        child: switch (slot) {
          _NullStatusSlot.loading => widget.loadingStatus!,
          _NullStatusSlot.noResults => NullStatus(
            label: UiLocalizations.of(context).noSearchResults,
            illustration: NullStatusIllustration.search,
          ),
          _NullStatusSlot.empty => widget.nullStatus!,
          _NullStatusSlot.content => widget.child,
        },
      ),
    );
  }
}

enum _NullStatusSlot { loading, empty, noResults, content }

class NullStatus extends StatefulWidget {
  final String? label;
  final String? description;
  final Widget? action;
  final NullStatusIllustration illustration;

  const NullStatus({
    super.key,
    this.label,
    this.description,
    this.action,
    this.illustration = NullStatusIllustration.data,
  });

  @override
  State<NullStatus> createState() => _NullStatusState();
}

class _NullStatusState extends State<NullStatus> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = sheetScrollController(context);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final NullStatus(:label, :description, :action, :illustration) = widget;
    final colorScheme = context.colorScheme;
    final compact = MediaQuery.sizeOf(context).height < _compactHeight;
    return Align(
      alignment: const Alignment(0.0, -0.2),
      child: SingleChildScrollView(
        controller: _controller,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _EnterItem(
                child: EmptyIllustration(
                  type: illustration,
                  dimension: compact ? 120 : 160,
                ),
              ),
              if (label != null) ...[
                SizedBox(height: compact ? 12 : 16),
                _EnterItem(
                  delay: _staggerStep,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: AppTextStyle.headline
                        .of(context)
                        .copyWith(color: colorScheme.onSurface),
                  ),
                ),
              ],
              if (description != null) ...[
                const SizedBox(height: 8),
                _EnterItem(
                  delay: _staggerStep * 2,
                  child: Text(
                    description,
                    textAlign: TextAlign.center,
                    style: AppTextStyle.subheadline
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 24),
                _EnterItem(
                  delay: _staggerStep * (description != null ? 3 : 2),
                  child: Theme(
                    data: Theme.of(context)
                        .copyWith(visualDensity: VisualDensity.standard),
                    child: action,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

const _compactHeight = 560.0;
const _staggerStep = Duration(milliseconds: 60);
const _enterRise = 12.0;

bool _skipsEntrance(BuildContext context) =>
    context.disableAnimations || isRouteArriving(context);

class _EnterItem extends StatefulWidget {
  final Duration delay;
  final Widget child;

  const _EnterItem({this.delay = Duration.zero, required this.child});

  @override
  State<_EnterItem> createState() => _EnterItemState();
}

class _EnterItemState extends State<_EnterItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool? _skipped;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: commonDuration + widget.delay,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_skipped != null) {
      return;
    }
    _skipped = _skipsEntrance(context);
    if (!_skipped!) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skipped = _skipped;
    if (skipped == null || skipped) {
      return widget.child;
    }
    final total = commonDuration + widget.delay;
    final start = widget.delay.inMicroseconds / total.inMicroseconds;
    final animation = start == 0
        ? _controller.view
        : _controller.drive(CurveTween(curve: Interval(start, 1)));
    return FadeSlideEnterTransition(
      animation: animation,
      distance: _enterRise,
      axis: Axis.vertical,
      child: widget.child,
    );
  }
}
