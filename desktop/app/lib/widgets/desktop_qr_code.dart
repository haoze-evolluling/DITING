library;

import 'package:material_ui/material_ui.dart';
import 'package:qr/qr.dart';

const _qrDark = Color(0xFF1A1A1C);
const _qrLight = Color(0xFFFFFFFF);

const _quietZone = 4;

class DesktopQrCode extends StatelessWidget {
  const DesktopQrCode({
    super.key,
    required this.data,
    this.size = 96,
    this.semanticLabel,
  });

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
