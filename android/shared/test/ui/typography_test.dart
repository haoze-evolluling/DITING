import 'dart:io';

import 'package:diting_shared/app/theme/manager.dart';
import 'package:diting_shared/ui/typography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('roles resolve their mobile type scale and color', (
    tester,
  ) async {
    final theme = _theme(TargetPlatform.android);
    late BuildContext context;
    await tester.pumpWidget(_host(theme, (value) => context = value));

    for (final role in AppTextRole.values) {
      final style = role.of(context);
      expect(style.fontSize, role.size, reason: role.name);
      expect(
        style.height! * style.fontSize!,
        closeTo(role.leading, 0.001),
        reason: role.name,
      );
      expect(style.fontWeight, role.weight, reason: role.name);
      expect(
        style.color,
        role.secondary
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.onSurface,
        reason: role.name,
      );
      expect(
        style.fontFeatures?.any((feature) => feature.feature == 'tnum') ??
            false,
        role.tabular || role.metric,
        reason: role.name,
      );
    }
  });

  testWidgets('desktop only raises the body roles', (tester) async {
    final theme = _theme(TargetPlatform.windows);
    late BuildContext context;
    await tester.pumpWidget(_host(theme, (value) => context = value));

    for (final role in AppTextRole.values) {
      expect(role.sizeOf(context), role.desktopSize ?? role.size);
      expect(role.leadingOf(context), role.desktopLeading ?? role.leading);
    }
    expect(AppTextRole.body.sizeOf(context), 16);
    expect(AppTextRole.body.leadingOf(context), 24);
    expect(AppTextRole.bodyStrong.sizeOf(context), 16);
    expect(AppTextRole.bodyStrong.leadingOf(context), 24);
  });

  test('page source uses only typography roles', () {
    final violations = <String>[];
    for (final root in ['android/shared/lib', 'android/app/lib']) {
      final directory = Directory('${_repoRoot().path}/$root');
      for (final entity in directory.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll('\\', '/');
        if (path.endsWith('shared/lib/ui/typography.dart')) continue;
        final source = entity.readAsStringSync();
        if (source.contains('AppTextStyle') ||
            source.contains('listTitleStyle') ||
            source.contains('listSubtitleStyle') ||
            source.contains('listCaptionStyle') ||
            source.contains('cardHeaderStyle')) {
          violations.add('${entity.path}: legacy typography API');
        }
        if (RegExp(r'\bfontSize\s*:').hasMatch(source)) {
          violations.add('${entity.path}: direct font size');
        }
        if (_hasTextHeightOverride(source)) {
          violations.add('${entity.path}: direct text line height');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}

bool _hasTextHeightOverride(String source) {
  for (final match in RegExp(
    r'\.copyWith\s*\(|TextStyle\s*\(',
  ).allMatches(source)) {
    final open = source.indexOf('(', match.start);
    var depth = 0;
    var inSingle = false;
    var inDouble = false;
    var escaped = false;
    for (var index = open; index < source.length; index++) {
      final char = source[index];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == '\\' && (inSingle || inDouble)) {
        escaped = true;
        continue;
      }
      if (char == "'" && !inDouble) {
        inSingle = !inSingle;
        continue;
      }
      if (char == '"' && !inSingle) {
        inDouble = !inDouble;
        continue;
      }
      if (inSingle || inDouble) continue;
      if (char == '(') {
        depth++;
      } else if (char == ')') {
        depth--;
        if (depth != 0) continue;
        final body = source.substring(open + 1, index);
        for (final height in RegExp(r'\bheight\s*:').allMatches(body)) {
          if (_depthAt(body, height.start) == 0) return true;
        }
        break;
      }
    }
  }
  return false;
}

int _depthAt(String source, int position) {
  var depth = 0;
  var inSingle = false;
  var inDouble = false;
  var escaped = false;
  for (var index = 0; index < position; index++) {
    final char = source[index];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == '\\' && (inSingle || inDouble)) {
      escaped = true;
      continue;
    }
    if (char == "'" && !inDouble) {
      inSingle = !inSingle;
      continue;
    }
    if (char == '"' && !inSingle) {
      inDouble = !inDouble;
      continue;
    }
    if (inSingle || inDouble) continue;
    if (char == '(') depth++;
    if (char == ')') depth--;
  }
  return depth;
}

ThemeData _theme(TargetPlatform platform) => buildAppTheme(
  const AppThemeSpec(
    seedColor: Color(0xFF4C6FFF),
    brightness: Brightness.light,
  ),
  platform: platform,
).copyWith(platform: platform);

Widget _host(ThemeData theme, ValueChanged<BuildContext> capture) {
  return MaterialApp(
    theme: theme,
    home: Builder(
      builder: (context) {
        capture(context);
        return const SizedBox.shrink();
      },
    ),
  );
}

Directory _repoRoot() {
  var directory = Directory.current;
  while (!Directory('${directory.path}/.git').existsSync()) {
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Repository root not found from ${Directory.current}');
    }
    directory = parent;
  }
  return directory;
}
