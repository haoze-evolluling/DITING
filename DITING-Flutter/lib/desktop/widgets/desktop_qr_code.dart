/// A QR code for a LAN console address, drawn from the same encoder the old console used.
///
/// The old desktop console rendered this with npm `qrcode` (`LANWebCard.vue`): 160px, one module of
/// margin, dark `#1A1A1C` on white. Those two colours are deliberately not theme colours — a scanner
/// needs contrast, so an inverted dark-theme code is worse than useless. Kept here so the card cannot
/// drift into a hand-rolled matrix.
library;

import 'package:material_ui/material_ui.dart';
import 'package:qr/qr.dart';

/// Module colours, matching the console's QR options.
const _qrDark = Color(0xFF1A1A1C);
const _qrLight = Color(0xFFFFFFFF);

/// Quiet zone in modules; the QR spec asks for four, and the console's `margin: 1` plus its white
/// padding came out near this after scaling.
const _quietZone = 4;

class DesktopQrCode extends StatelessWidget {
  const DesktopQrCode({
    super.key,
    required this.data,
    this.size = 96,
    this.semanticLabel,
  });

  /// What the code encodes, e.g. `http://192.168.1.10:15353`.
  final String data;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final image = QrImage(
      QrCode(
        payload: QrPayload.fromString(data),
        errorCorrectLevel: QrErrorCorrectLevel.medium,
      ),
    );
    return Semantics(
      label: semanticLabel,
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _QrPainter(image)),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  const _QrPainter(this.image);

  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    final modules = image.moduleCount + _quietZone * 2;
    final moduleSize = size.shortestSide / modules;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = _qrLight,
    );
    final dark = Paint()..color = _qrDark;
    for (var row = 0; row < image.moduleCount; row++) {
      for (var col = 0; col < image.moduleCount; col++) {
        if (!image.isDark(row, col)) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            (col + _quietZone) * moduleSize,
            (row + _quietZone) * moduleSize,
            moduleSize + 0.5,
            moduleSize + 0.5,
          ),
          dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) => oldDelegate.image != image;
}
