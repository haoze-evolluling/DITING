library;

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:diting_shared/ui/inherited.dart';
import 'package:diting_shared/ui/navigator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

final List<String> _diagnostics = <String>[];
final List<String> _notes = <String>[];

const List<String> _structureTypes = <String>[
  'AppBar',
  'CommonScaffold',
  'NavigationDock',
  'ListHeader',
  'SegmentedControl',
  'PageBody',
  'FloatingHeader',
  'Scaffold',
  'Card',
  'Tile',
  'Image',
  'Chart',
  'EditableText',
  'InputDecorator',
  'TextField',
  'NullStatus',
  'Button',
  'CustomPaint',
  'Icon',
  'Screen',
  'Frame',
];

void installDebugProbe() {
  if (!kDebugMode) return;
  final previous = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final text = details.exceptionAsString().split('\n').first;
    if (text.contains('RenderBox') ||
        text.contains('overflowed') ||
        text.contains('viewport') ||
        text.contains('infinite') ||
        text.contains('assertion')) {
      if (_diagnostics.length < 60) _diagnostics.add(text);
    }
    previous?.call(details);
  };

  developer.registerExtension('ext.diting.go', (
    String name,
    Map<String, String> args,
  ) async {
    final loc = args['loc'] ?? '/';
    _diagnostics.clear();
    rootNavigatorKey.currentState?.popUntil((route) => route is! PopupRoute);
    final context = rootNavigatorKey.currentContext;
    if (context != null) GoRouter.of(context).go(loc);
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'ok': context != null, 'loc': loc}),
    );
  });

  developer.registerExtension('ext.diting.back', (
    String name,
    Map<String, String> args,
  ) async {
    final nav = rootNavigatorKey.currentState;
    final popped = nav?.canPop() ?? false;
    if (popped) nav!.pop();
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'popped': popped}),
    );
  });

  developer.registerExtension('ext.diting.probe', (
    String name,
    Map<String, String> args,
  ) async {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) {
      return developer.ServiceExtensionResponse.result(
        jsonEncode({'error': 'no root element'}),
      );
    }
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final dpr = view.devicePixelRatio;
    final size = view.physicalSize / dpr;
    final vp = view.viewPadding;
    final vi = view.viewInsets;
    final texts = <Map<String, Object?>>[];
    final boxes = <Map<String, Object?>>[];
    final seen = <String>{};
    _notes.clear();

    void visit(Element element, double vpBottom, bool hz, bool inBar) {
      var clipBottom = vpBottom;
      final widget = element.widget;
      if (widget is Scrollable) {
        final dir = widget.axisDirection;
        if (dir == AxisDirection.left || dir == AxisDirection.right) {
          hz = true;
        } else {
          final box = element.renderObject;
          if (box is RenderBox && box.hasSize) {
            final bottom =
                (box.localToGlobal(Offset.zero) + Offset(0, box.size.height))
                    .dy;
            if (bottom < clipBottom) clipBottom = bottom;
          }
        }
      }
      if (widget is Visibility && !widget.visible) return;
      if (widget is Offstage && widget.offstage) return;
      if (widget is SliverPadding) {
        final pad = widget.padding;
        final top = pad is EdgeInsets ? pad.top : -999.0;
        _notes.add('SliverPadding t=${_r(top)}');
      }
      final type = widget.runtimeType.toString();

      if (type == 'AppBar' || type == 'NavigationDock') inBar = true;
      if (type == 'PageBody') {
        final mq = MediaQuery.of(element);
        _notes.add(
          'PageBody padTop=${_r(mq.padding.top)} '
          'float=${_r(FloatingBarScope.of(element) ?? -1)}',
        );
      }
      final renderObject = element.renderObject;
      if (renderObject is RenderBox && renderObject.hasSize) {
        final rect =
            renderObject.localToGlobal(Offset.zero) & renderObject.size;
        if (widget is RichText) {
          final label = widget.text.toPlainText();
          final style = widget.text.style;
          if (label.trim().isNotEmpty && label.length < 200) {
            final key = '$label@${rect.left.round()},${rect.top.round()}';
            if (seen.add(key)) {
              texts.add(<String, Object?>{
                's': label,
                'x': _r(rect.left),
                'y': _r(rect.top),
                'w': _r(rect.width),
                'h': _r(rect.height),
                'fs': style?.fontSize,
                'hz': hz,
                'bar': inBar,
                'vb': _r(clipBottom),
                'clip': !hz && _r(rect.right) > size.width + 0.6,
                'off':
                    rect.bottom < 0 || rect.top > size.height || rect.right < 0,
              });
            }
          }
        } else if (_structureTypes.any(type.contains)) {
          boxes.add(<String, Object?>{
            'k': type,
            'x': _r(rect.left),
            'y': _r(rect.top),
            'w': _r(rect.width),
            'h': _r(rect.height),
          });
        }
      }
      element.visitChildren((child) => visit(child, clipBottom, hz, inBar));
    }

    visit(root, size.height, false, false);
    final payload = <String, Object?>{
      'screen': <String, Object?>{
        'w': _r(size.width),
        'h': _r(size.height),
        'dpr': dpr,
      },
      'pad': <String, Object?>{
        'top': _r(vp.top),
        'bottom': _r(vp.bottom),
        'left': _r(vp.left),
        'right': _r(vp.right),
        'insBottom': _r(vi.bottom),
      },
      'texts': texts,
      'boxes': boxes,
      'diag': _diagnostics,
      'notes': _notes,
    };
    return developer.ServiceExtensionResponse.result(jsonEncode(payload));
  });
}

double _r(double v) => (v * 10).roundToDouble() / 10;
