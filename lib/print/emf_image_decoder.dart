import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:image/image.dart' as img;
import 'package:win32/win32.dart';

class EmfImageDecoder {
  EmfImageDecoder._();

  static Future<Uint8List?> renderEmfToPng(Uint8List emfBytes, {int dpi = 400}) async {
    if (!Platform.isWindows) return null;
    final tempDir = Directory.systemTemp;
    final tempFile = File('${tempDir.path}\\emf_${DateTime.now().microsecondsSinceEpoch}.emf');
    try {
      await tempFile.writeAsBytes(emfBytes);
      final hEnhMetaFile = GetEnhMetaFile(tempFile.path.toNativeUtf16());
      if (hEnhMetaFile == 0) return null;

      try {
        final header = calloc<ENHMETAHEADER>();
        GetEnhMetaFileHeader(hEnhMetaFile, sizeOf<ENHMETAHEADER>(), header);

        final rect = header.ref.rclFrame;
        final widthMm = (rect.right - rect.left).abs() / 100.0;
        final heightMm = (rect.bottom - rect.top).abs() / 100.0;
        var widthPx = (widthMm * dpi / 25.4).round();
        var heightPx = (heightMm * dpi / 25.4).round();
        if (widthPx < 1) widthPx = 1024;
        if (heightPx < 1) heightPx = 768;

        final hdcScreen = GetDC(0);
        final hdcMem = CreateCompatibleDC(hdcScreen);
        final hBitmap = CreateCompatibleBitmap(hdcScreen, widthPx, heightPx);
        final hOldBitmap = SelectObject(hdcMem, hBitmap);

        final brush = CreateSolidBrush(0x00FFFFFF);
        final rectPaint = calloc<RECT>()
          ..ref.left = 0
          ..ref.top = 0
          ..ref.right = widthPx
          ..ref.bottom = heightPx;
        FillRect(hdcMem, rectPaint, brush);
        DeleteObject(brush);

        final playRect = calloc<RECT>()
          ..ref.left = 0
          ..ref.top = 0
          ..ref.right = widthPx
          ..ref.bottom = heightPx;
        PlayEnhMetaFile(hdcMem, hEnhMetaFile, playRect);

        final bmi = calloc<BITMAPINFO>();
        bmi.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
        bmi.ref.bmiHeader.biWidth = widthPx;
        bmi.ref.bmiHeader.biHeight = -heightPx;
        bmi.ref.bmiHeader.biPlanes = 1;
        bmi.ref.bmiHeader.biBitCount = 32;
        bmi.ref.bmiHeader.biCompression = BI_RGB;

        final bufferSize = widthPx * heightPx * 4;
        final pixels = calloc<Uint8>(bufferSize);
        GetDIBits(hdcMem, hBitmap, 0, heightPx, pixels, bmi, DIB_RGB_COLORS);

        final image = img.Image(width: widthPx, height: heightPx);
        for (var y = 0; y < heightPx; y++) {
          for (var x = 0; x < widthPx; x++) {
            final idx = (y * widthPx + x) * 4;
            final b = pixels[idx + 0];
            final g = pixels[idx + 1];
            final r = pixels[idx + 2];
            image.setPixelRgba(x, y, r, g, b, 255);
          }
        }

        final png = img.encodePng(image);

        SelectObject(hdcMem, hOldBitmap);
        DeleteObject(hBitmap);
        DeleteDC(hdcMem);
        ReleaseDC(0, hdcScreen);
        free(header);
        free(rectPaint);
        free(playRect);
        free(bmi);
        free(pixels);
        return Uint8List.fromList(png);
      } finally {
        DeleteEnhMetaFile(hEnhMetaFile);
      }
    } finally {
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
    }
  }

  static Future<String?> decodeBarcode(Uint8List emfBytes) async {
    if (!Platform.isWindows) return null;
    for (final dpi in [400, 300, 600, 500, 250]) {
      try {
        final png = await renderEmfToPng(emfBytes, dpi: dpi);
        if (png == null) continue;
        // Try direct decode
        var result = await zx.readBarcodeImagePathBytes(png);
        if (result.isValid && result.text.isNotEmpty) {
          return result.text;
        }
        // Try grayscale
        final image = img.decodeImage(png);
        if (image != null) {
          final gray = img.grayscale(image);
          final grayPng = img.encodePng(gray);
          result = await zx.readBarcodeImagePathBytes(Uint8List.fromList(grayPng));
          if (result.isValid && result.text.isNotEmpty) {
            return result.text;
          }
          // Try binary threshold
          final thresh = img.Image(width: gray.width, height: gray.height);
          for (var y = 0; y < gray.height; y++) {
            for (var x = 0; x < gray.width; x++) {
              final p = gray.getPixel(x, y);
              final lum = img.getLuminance(p);
              thresh.setPixelRgba(x, y, lum > 128 ? 255 : 0, lum > 128 ? 255 : 0, lum > 128 ? 255 : 0, 255);
            }
          }
          final threshPng = img.encodePng(thresh);
          result = await zx.readBarcodeImagePathBytes(Uint8List.fromList(threshPng));
          if (result.isValid && result.text.isNotEmpty) {
            return result.text;
          }
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }
}
