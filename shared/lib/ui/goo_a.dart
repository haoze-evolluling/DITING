// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'goo.dart';

double _pillDistance(Rect pill, Offset point) =>
    _roundedDistance(pill, pill.shortestSide / 2, point);

double _roundedDistance(Rect rect, double radius, Offset point) {
  final round = math.min(radius, rect.shortestSide / 2);
  final qx = (point.dx - rect.center.dx).abs() - rect.width / 2 + round;
  final qy = (point.dy - rect.center.dy).abs() - rect.height / 2 + round;
  return Offset(math.max(qx, 0), math.max(qy, 0)).distance +
      math.min(math.max(qx, qy), 0) -
      round;
}

const _seedTurns = 4;

enum _Reach { deep, flowing, clear }

/// Fans out of [b]'s center where it flows into [a], each ray stepping as far
/// as no distance can cross zero, to where the blend ends or deep into [a];
/// convex, [a] holds all between the first and last of a run of those deep.
/// Of [turns] rays, every [_seedTurns]th goes first, the rest only where the
/// pair flows and until one cast midway lies within [tolerance] of the chord.
Path? _bridge(
  Rect a,
  double radius,
  Rect b,
  double blend, {
  required int turns,
  required double tolerance,
}) {
  if (blend <= 0 || b.isEmpty) {
    return null;
  }
  double toA(Offset point) => _roundedDistance(a, radius, point);
  double field(Offset point) =>
      _smoothMin(toA(point), _pillDistance(b, point), blend);
  final center = b.center;
  final limit = b.longestSide / 2 + a.longestSide + blend;
  Offset reach(Offset direction) {
    var inside = 0.0;
    for (var distance = 0.0; distance < limit;) {
      final point = center + direction * distance;
      final platter = toA(point);
      if (platter < -blend) {
        return point;
      }
      final depth = _smoothMin(platter, _pillDistance(b, point), blend);
      if (depth >= 0) {
        var outside = distance;
        for (var step = 0; step < 4; step++) {
          final middle = (inside + outside) / 2;
          if (field(center + direction * middle) < 0) {
            inside = middle;
          } else {
            outside = middle;
          }
        }
        break;
      }
      inside = distance;
      distance += math.max(0.5, math.min(-depth, platter + blend));
    }
    return center + direction * inside;
  }

  final ends = List<Offset?>.filled(turns, null);
  final depths = List<double>.filled(turns, 0);
  _Reach reachOf(int turn) {
    final depth = depths[turn % turns];
    return depth < -blend
        ? _Reach.deep
        : depth < blend
        ? _Reach.flowing
        : _Reach.clear;
  }

  void cast(int turn) {
    final end = reach(Offset.fromDirection(turn / turns * 2 * math.pi));
    ends[turn] = end;
    depths[turn] = toA(end);
  }

  void skip(int from, int to) {
    for (var turn = from + 1; turn < to; turn++) {
      if (ends[turn] == null) {
        depths[turn] = depths[from];
      }
    }
  }

  void refine(int from, int to) {
    if (to - from < 2) {
      return;
    }
    final alike = reachOf(from) == reachOf(to);
    if (alike && reachOf(from) != _Reach.flowing) {
      skip(from, to);
      return;
    }
    final middle = (from + to) ~/ 2;
    cast(middle);
    if (alike &&
        reachOf(middle) == reachOf(from) &&
        _offChord(ends[from]!, ends[to % turns]!, ends[middle]!) <= tolerance) {
      skip(from, to);
      return;
    }
    refine(from, middle);
    refine(middle, to);
  }

  for (var turn = 0; turn < turns; turn += _seedTurns) {
    cast(turn);
  }
  for (var turn = 0; turn < turns; turn += _seedTurns) {
    refine(turn, turn + _seedTurns);
  }
  final flows = [for (final depth in depths) depth < blend];
  if (!flows.contains(true)) {
    return null;
  }
  bool deep(int turn) => depths[turn] < -blend;
  final first = flows.contains(false) ? flows.indexOf(false) : 0;
  final path = Path();
  var fan = <int>[];
  void close() {
    if (fan.length > 1) {
      final rim = [
        for (final (index, turn) in fan.indexed)
          if (ends[turn] case final end?
              when index == 0 ||
                  index == fan.length - 1 ||
                  !deep(fan[index - 1]) ||
                  !deep(turn) ||
                  !deep(fan[index + 1]))
            end,
      ];
      path.addPolygon([center, ..._douglasPeucker(rim, tolerance)], true);
    }
    fan = [];
  }

  for (var index = 0; index <= turns; index++) {
    final turn = (first + index) % turns;
    if (flows[turn]) {
      fan.add(turn);
    } else {
      close();
    }
  }
  close();
  return path;
}

double _offChord(Offset from, Offset to, Offset point) {
  final chord = to - from;
  final length = chord.distance;
  final offset = point - from;
  return length == 0
      ? offset.distance
      : (offset.dx * chord.dy - offset.dy * chord.dx).abs() / length;
}

List<Offset> _douglasPeucker(List<Offset> points, double tolerance) {
  if (points.length < 3) {
    return points;
  }
  final kept = List<bool>.filled(points.length, false)
    ..[0] = true
    ..[points.length - 1] = true;
  void split(int from, int to) {
    var farthest = 0.0;
    var at = -1;
    for (var index = from + 1; index < to; index++) {
      final off = _offChord(points[from], points[to], points[index]);
      if (off > farthest) {
        farthest = off;
        at = index;
      }
    }
    if (at >= 0 && farthest > tolerance) {
      kept[at] = true;
      split(from, at);
      split(at, to);
    }
  }

  split(0, points.length - 1);
  return [
    for (final (index, point) in points.indexed)
      if (kept[index]) point,
  ];
}

double _smoothMin(double a, double b, double blend) {
  final h = (0.5 + 0.5 * (b - a) / blend).clamp(0.0, 1.0);
  return lerpDouble(b, a, h)! - blend * h * (1 - h);
}

/// What [a] and [b] add to their own outlines between the centers of their
/// facing ends: a neck, or a bulge from each toward the other. Only where they
/// flow together, so each keeps its superellipse elsewhere, as the shader's
/// line does.
Path? _neck(Rect a, Rect b, double blend) {
  final from = a.right - a.shortestSide / 2;
  final to = b.left + b.shortestSide / 2;
  if (blend <= 0 || to <= from || b.left - a.right >= blend) {
    return null;
  }
  double field(Offset point) =>
      _smoothMin(_pillDistance(a, point), _pillDistance(b, point), blend);
  double axisAt(double x) =>
      lerpDouble(a.center.dy, b.center.dy, (x - from) / (to - from))!;
  final reach = math.max(a.height, b.height) / 2 + blend;
  double edge(double x, double toward) {
    final axis = axisAt(x);
    var inside = 0.0;
    var outside = reach;
    for (var step = 0; step < 16; step++) {
      final middle = (inside + outside) / 2;
      if (field(Offset(x, axis + toward * middle)) < 0) {
        inside = middle;
      } else {
        outside = middle;
      }
    }
    return axis + toward * (inside + outside) / 2;
  }

  double tip(double inside, double outside) {
    for (var step = 0; step < 16; step++) {
      final middle = (inside + outside) / 2;
      if (field(Offset(middle, axisAt(middle))) < 0) {
        inside = middle;
      } else {
        outside = middle;
      }
    }
    return (inside + outside) / 2;
  }

  final path = Path();
  final steps = math.max(2, ((to - from) / _neckStep).ceil());
  var top = <Offset>[];
  var bottom = <Offset>[];
  void close() {
    if (top.isEmpty) {
      return;
    }
    path.addPolygon([...top, ...bottom.reversed], true);
    top = [];
    bottom = [];
  }

  bool flows(Offset point) =>
      (_pillDistance(a, point) - _pillDistance(b, point)).abs() < blend;

  double? previous;
  var wasInside = false;
  for (var index = 0; index <= steps; index++) {
    final x = from + (to - from) * index / steps;
    final inside = field(Offset(x, axisAt(x))) < 0;
    final upper = inside ? Offset(x, edge(x, -1)) : null;
    final lower = inside ? Offset(x, edge(x, 1)) : null;
    if (upper != null && lower != null && (flows(upper) || flows(lower))) {
      if (top.isEmpty && previous != null && !wasInside) {
        final start = tip(x, previous);
        top.add(Offset(start, axisAt(start)));
      }
      top.add(upper);
      bottom.add(lower);
    } else if (top.isNotEmpty) {
      if (!inside) {
        final end = tip(previous!, x);
        top.add(Offset(end, axisAt(end)));
      }
      close();
    }
    previous = x;
    wasInside = inside;
  }
  close();
  return path;
}
