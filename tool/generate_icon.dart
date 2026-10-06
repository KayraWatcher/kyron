import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

Future<void> main() async {
  // Create a professional KYRON icon
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = Size(512, 512);
  
  // Background gradient
  final bgPaint = Paint()
    ..shader = ui.Gradient.linear(
      Offset(0, 0),
      Offset(size.width, size.height),
      [const Color(0xFF0B0F16), const Color(0xFF131924)],
      [0.0, 1.0],
    );
  canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);
  
  // Rounded corners
  final rrect = RRect.fromRectAndRadius(
    Rect.fromLTWH(0, 0, size.width, size.height),
    Radius.circular(80),
  );
  canvas.clipRRect(rrect);
  
  // Draw subtle grid pattern
  final gridPaint = Paint()
    ..color = const Color(0xFFD4A017).withOpacity(0.03)
    ..strokeWidth = 0.5
    ..style = PaintingStyle.stroke;
  
  for (double x = 0; x <= size.width; x += 32) {
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
  }
  for (double y = 0; y <= size.height; y += 32) {
    canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
  }
  
  // Draw main candlestick symbol
  final centerX = size.width / 2;
  final centerY = size.height / 2;
  
  // Candlestick body
  final candlePaint = Paint()
    ..shader = ui.Gradient.linear(
      Offset(centerX - 48, centerY - 70),
      Offset(centerX + 48, centerY + 70),
      [const Color(0xFFD4A017), const Color(0xFFB8860B)],
      [0.0, 1.0],
    );
  
  final candleRect = RRect.fromRectAndRadius(
    Rect.fromCenter(center: Offset(centerX, centerY), width: 96, height: 140),
    Radius.circular(8),
  );
  canvas.drawRRect(candleRect, candlePaint);
  
  // Upper wick
  final wickPaint = Paint()..shader = ui.Gradient.linear(
    Offset(centerX - 4, centerY - 120),
    Offset(centerX + 4, centerY - 70),
    [const Color(0xFFD4A017), const Color(0xFFB8860B)],
    [0.0, 1.0],
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(centerX, centerY - 95), width: 8, height: 50),
      Radius.circular(4),
    ),
    wickPaint,
  );
  
  // Lower wick
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(centerX, centerY + 95), width: 8, height: 50),
      Radius.circular(4),
    ),
    wickPaint,
  );
  
  // Upward arrow
  final arrowPath = Path()
    ..moveTo(centerX, centerY - 100)
    ..lineTo(centerX - 20, centerY - 80)
    ..lineTo(centerX + 20, centerY - 80)
    ..close();
  canvas.drawPath(arrowPath, candlePaint);
  
  // KYRON text
  final textPainter = TextPainter(
    text: TextSpan(
      text: 'KYRON',
      style: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: const Color(0xFFD4A017).withOpacity(0.3),
        fontFamily: 'Roboto',
      ),
    ),
    textDirection: TextDirection.ltr,
  );
  textPainter.layout();
  textPainter.paint(canvas, Offset(centerX - textPainter.width / 2, centerY + 140));
  
  // Outer ring
  final ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..shader = ui.Gradient.linear(
      Offset(0, 0),
      Offset(size.width, size.height),
      [const Color(0xFFD4A017), const Color(0xFFB8860B)],
      [0.0, 1.0],
    );
  canvas.drawCircle(Offset(centerX, centerY), 230, ringPaint);
  
  // Generate image
  final picture = recorder.endRecording();
  final img = await picture.toImage(512, 512);
  final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
  final pngBytes = byteData!.buffer.asUint8List();
  
  // Save to file
  final file = File('assets/icon/icon.png');
  await file.writeAsBytes(pngBytes);
  print('Icon generated successfully!');
}