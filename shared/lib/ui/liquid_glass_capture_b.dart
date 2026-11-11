// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'liquid_glass.dart';

class _LiquidGlassHostLayer extends ContainerLayer {
  static int _pass = 0;

  double devicePixelRatio = 1;
  LiquidGlassQuality quality = LiquidGlassQuality.ultra;
  Rect bounds = Rect.zero;

  final _atlases = <({ui.Image image, List<_Band> bands})>[];

  Set<_LiquidGlassLayer> _panes = {};

  @override
  void addToScene(ui.SceneBuilder builder) {
    _capture();
    super.addToScene(builder);
  }

  @override
  void dispose() {
    for (final pane in _panes) {
      pane._dropCaptured();
    }
    _panes = {};
    for (final atlas in _atlases) {
      atlas.image.dispose();
    }
    _atlases.clear();
    super.dispose();
  }

  /// A pane over one painted before it in the same root, but for one of its
  /// own group, sits a level above it, and reads a capture with that one drawn
  /// as glass.
  void _capture() {
    _pass++;
    final found = <_Behind>[];
    _gather(this, Matrix4.identity(), this, Matrix4.identity(), [], found);
    final panes = {for (final entry in found) entry.pane};
    for (final pane in _panes.difference(panes)) {
      pane._dropCaptured();
    }
    _panes = panes;
    final placed = <_Behind>[];
    for (final entry in found) {
      if (_place(entry)) {
        placed.add(entry);
        if (entry.style.haze > 0) {
          final haze = _Behind.hazeOf(entry);
          if (_place(haze)) {
            entry.haze = haze;
          }
        }
      } else {
        entry.pane._captureNothing(_pass);
      }
    }
    var levels = 0;
    for (final (index, entry) in placed.indexed) {
      final group = entry.pane.group;
      for (final before in placed.take(index)) {
        if ((identical(entry.root, this) ||
                before.ancestors.contains(entry.root)) &&
            (group == null || !identical(before.pane.group, group)) &&
            before.device.overlaps(entry.reach)) {
          entry.level = math.max(entry.level, before.level + 1);
        }
      }
      levels = math.max(levels, entry.level + 1);
    }
    var snapshots = 0;
    var keptBands = 0;
    for (var level = 0; level < levels; level++) {
      final members = [
        for (final entry in placed)
          if (entry.level == level) entry,
      ];
      final (:atlas, :taken, :kept) = _snapshot(level, [
        for (final entry in members) ...[entry, ?entry.haze],
      ]);
      if (taken) {
        snapshots++;
        keptBands += kept;
      }
      for (final entry in members) {
        entry.atlas = atlas;
        _publish(entry, atlas);
      }
    }
    while (_atlases.length > levels) {
      _atlases.removeLast().image.dispose();
    }
    assert(() {
      LiquidGlassHost.debugLastCapture = (
        snapshots: snapshots,
        keptBands: keptBands,
        panes: [
          for (final entry in placed)
            (
              pane: entry.device,
              slot: entry.slot,
              place: entry.place,
              scale: entry.texelsPerDp,
              level: entry.level,
              atlas: entry.atlas!,
            ),
        ],
      );
      return true;
    }());
  }

  void _gather(
    ContainerLayer layer,
    Matrix4 toHost,
    ContainerLayer root,
    Matrix4 rootToHost,
    List<ContainerLayer> chain,
    List<_Behind> found,
  ) {
    chain.add(layer);
    for (Layer? child = layer.firstChild; child != null;) {
      switch (child) {
        case final _LiquidGlassLayer pane:
          final style = switch (quality) {
            LiquidGlassQuality.standard => pane.style._standard,
            LiquidGlassQuality.ultra => pane.style,
          };
          final storage = toHost.storage;
          final stretch = math.max(storage[0].abs(), storage[5].abs());
          found.add(
            _Behind(
              pane,
              pane.steadyFrost && stretch > 0
                  ? style.copyWith(blur: style.blur / stretch)
                  : style,
              toHost,
              root,
              rootToHost,
              chain.toSet(),
            ),
          );
        case final ContainerLayer container:
          final offscreen = _drawsOffscreen(container);
          _gather(
            container,
            _within(container, toHost),
            offscreen ? container : root,
            offscreen ? toHost : rootToHost,
            chain,
            found,
          );
      }
      child = child.nextSibling;
    }
    chain.removeLast();
  }

  /// Snaps the slot to the capture's pixels so still content stays put while the pane moves.
  bool _place(_Behind entry) {
    final pane = entry.pane;
    final style = entry.style;
    final hazed = entry.hazed;
    final blur = hazed ? style.hazeBlur : style.blur;
    final storage = entry.toHost.storage;
    final stretch = math.max(storage[0].abs(), storage[5].abs());
    final device = entry.device;
    if (stretch == 0 || device.isEmpty || !device.overlaps(bounds)) {
      pane._held = null;
      return false;
    }
    final hold = hazed ? null : pane.hold;
    final sweep = hold == null
        ? device
        : device.expandToInclude(MatrixUtils.transformRect(entry.toHost, hold));
    final bend = math.max(0.0, -style.refraction) + style.dispersion;
    final reach = (3 * (blur + style.rimBlur) + bend + 2) * stretch;
    entry.reach = sweep.inflate(
      (_levelReach * (blur + style.rimBlur) + bend) * stretch,
    );
    final needed = device.inflate(reach).intersect(bounds);
    final covered = sweep.inflate(reach).intersect(bounds);
    final longest = math.max(covered.width, covered.height) * devicePixelRatio;
    final captured = hold != null && pane.program != null
        ? math.min(blur, pane.holdFrost ?? blur)
        : blur;
    final divisor = math.max(
      math.min(
        _maxDivisor,
        math.max(
          1,
          (captured * stretch * devicePixelRatio / _captureFrost).floor(),
        ),
      ),
      (longest / _maxCaptureSide).ceil(),
    );
    final scale = devicePixelRatio / divisor;
    final frost = captured * stretch * scale;
    final softness = divisor > 1 ? _captureSoftness : 0.0;
    final blurSigma = frost > softness
        ? math.sqrt(frost * frost - softness * softness)
        : 0.0;
    final held = pane._held;
    final _Placement placement;
    if (hold != null &&
        held != null &&
        held.texelsPerDp == scale &&
        held.blurSigma >= blurSigma &&
        blurSigma >= held.blurSigma * _heldFrostShare &&
        _encloses(held.slot, needed)) {
      placement = held;
    } else {
      final left = (covered.left * scale).floorToDouble();
      final top = (covered.top * scale).floorToDouble();
      final right = (covered.right * scale).ceilToDouble();
      final bottom = (covered.bottom * scale).ceilToDouble();
      placement = (
        slot: Rect.fromLTRB(
          left / scale,
          top / scale,
          right / scale,
          bottom / scale,
        ),
        texels: Size(right - left, bottom - top),
        texelsPerDp: scale,
        heldFrost: math.max(frost, softness),
        blurSigma: blurSigma,
      );
    }
    if (!hazed) {
      pane._held = hold == null ? null : placement;
    }
    entry
      ..texelsPerDp = placement.texelsPerDp
      ..heldFrost = placement.heldFrost
      ..blurSigma = placement.blurSigma
      ..slot = placement.slot
      ..texels = placement.texels;
    return true;
  }

  ({ui.Image atlas, bool taken, int kept}) _snapshot(
    int level,
    List<_Behind> members,
  ) {
    // Slots that blur alike share one blurring layer; the rest go alone.
    final classes = <Object, List<_Behind>>{};
    for (final entry in members) {
      (classes[entry.blurSigma == 0 ? entry : entry.blurSigma] ??= []).add(
        entry,
      );
    }
    double step(double extent) => (extent / _atlasStep).ceil() * _atlasStep;
    final bands = <_Band>[];
    final pictures = <ui.Picture>[];
    var top = 0.0;
    for (final entries in classes.values) {
      var bottom = 0.0;
      var width = 0.0;
      for (final entry in entries) {
        entry.place = Offset(0, top + bottom) & entry.texels;
        bottom += entry.texels.height;
        width = math.max(width, entry.texels.width);
      }
      final rect = Rect.fromLTWH(0, top, step(width), step(bottom));
      final sigma = entries.first.blurSigma;
      final drawn = <Object?>[sigma, rect.size];
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      for (final entry in entries) {
        final place = entry.place.shift(-rect.topLeft);
        drawn
          ..add(place)
          ..add(entry.slot)
          ..addAll(entry.rootToHost.storage);
        canvas
          ..save()
          ..clipRect(place)
          ..translate(place.left, place.top)
          ..scale(entry.texelsPerDp)
          ..translate(-entry.slot.left, -entry.slot.top)
          ..transform(entry.rootToHost.storage);
        _Replay(canvas, drawn, entry).run();
        canvas.restore();
      }
      bands.add((rect: rect, sigma: sigma, drawn: drawn));
      pictures.add(recorder.endRecording());
      top = rect.bottom;
    }
    final size = Size(
      bands.fold(0.0, (width, band) => math.max(width, band.rect.width)),
      top,
    );
    final previous = level < _atlases.length ? _atlases[level] : null;
    final last = previous?.bands ?? const <_Band>[];
    if (previous != null &&
        previous.image.width == size.width &&
        previous.image.height == size.height &&
        last.length == bands.length &&
        bands.indexed.every(
          (band) =>
              band.$2.rect == last[band.$1].rect &&
              listEquals(band.$2.drawn, last[band.$1].drawn),
        )) {
      for (final picture in pictures) {
        picture.dispose();
      }
      return (atlas: previous.image, taken: false, kept: 0);
    }
    // Skia retains an image's source while it lives, so copying the last capture retains all
    // before.
    final carry =
        LiquidGlassHost.debugCarryBandsOverride ??
        ui.ImageFilter.isShaderFilterSupported;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    var kept = 0;
    for (final (index, band) in bands.indexed) {
      final picture = pictures[index];
      final old = carry
          ? last.where((old) => listEquals(old.drawn, band.drawn)).firstOrNull
          : null;
      if (old != null) {
        canvas.drawImageRect(
          previous!.image,
          old.rect,
          band.rect,
          Paint()
            ..filterQuality = FilterQuality.none
            ..blendMode = BlendMode.src,
        );
        kept++;
      } else {
        final sigma = band.sigma;
        canvas
          ..save()
          ..clipRect(band.rect);
        if (sigma > 0) {
          canvas.saveLayer(
            band.rect,
            Paint()
              ..imageFilter = ui.ImageFilter.blur(
                sigmaX: sigma,
                sigmaY: sigma,
                tileMode: TileMode.clamp,
              ),
          );
        }
        // Impeller filters a layer under the transform current at its restore.
        canvas
          ..save()
          ..translate(band.rect.left, band.rect.top)
          ..drawPicture(picture)
          ..restore();
        if (sigma > 0) {
          canvas.restore();
        }
        canvas.restore();
      }
      picture.dispose();
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(size.width.toInt(), size.height.toInt());
    picture.dispose();
    if (previous == null) {
      _atlases.add((image: image, bands: bands));
    } else {
      previous.image.dispose();
      _atlases[level] = (image: image, bands: bands);
    }
    return (atlas: image, taken: true, kept: kept);
  }

  void _publish(_Behind entry, ui.Image atlas) {
    final pane = entry.pane;
    final storage = entry.toHost.storage;
    final haze = entry.haze;
    pane._captureFrom(
      _pass,
      atlas,
      [
        ..._sampling(entry),
        1 / (devicePixelRatio * math.max(storage[0].abs(), storage[5].abs())),
        entry.heldFrost,
        ...haze == null ? _noHaze : _sampling(haze),
        if (haze == null) 0 else entry.style.haze,
        entry.veil.r,
        entry.veil.g,
        entry.veil.b,
        entry.veil.a,
      ],
      identical(entry.root, this) ? BlendMode.srcOver : BlendMode.src,
      entry.style,
    );
  }

  List<double> _sampling(_Behind slot) {
    final pane = slot.pane;
    final storage = slot.toHost.storage;
    final place = slot.place;
    final scale = slot.texelsPerDp;
    final texelsPerPaneX = storage[0] * scale;
    final texelsPerPaneY = storage[5] * scale;
    final originX =
        place.left +
        (storage[0] * pane.rect.left + storage[12] - slot.slot.left) * scale;
    final originY =
        place.top +
        (storage[5] * pane.rect.top + storage[13] - slot.slot.top) * scale;
    return [
      -originX / texelsPerPaneX,
      -originY / texelsPerPaneY,
      1 / texelsPerPaneX,
      1 / texelsPerPaneY,
      place.left + 0.5,
      place.top + 0.5,
      place.right - 0.5,
      place.bottom - 0.5,
    ];
  }
}
