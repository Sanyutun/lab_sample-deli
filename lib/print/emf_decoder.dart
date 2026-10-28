import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:image/image.dart' as img;
import 'package:win32/win32.dart';

class EmfDecoder {
  EmfDecoder._();

  /// Render EMF to image bytes (PNG)
  static Uint8List? renderEmfToPng(String emfPath, {int dpi = 400}) {
    if (!Platform.isWindows) return null;
    final hEnhMetaFile = GetEnhMetaFile(emfPath.toNativeUtf16());
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
          final a = pixels[idx + 3];
          image.setPixelRgba(x, y, r, g, b, a == 0 ? 255 : a);
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
  }

  /// Render from EMF bytes in memory
  static Uint8List? renderEmfBytesToPng(Uint8List emfBytes, {int dpi = 400}) {
    if (!Platform.isWindows) return null;
    // Write to temp file
    final tempDir = Directory.systemTemp;
    final tempFile = File('${tempDir.path}\\emf_${DateTime.now().millisecondsSinceEpoch}.emf');
    try {
      tempFile.writeAsBytesSync(emfBytes);
      final result = renderEmfToPng(tempFile.path, dpi: dpi);
      return result;
    } finally {
      try {
        if (tempFile.existsSync()) tempFile.deleteSync();
      } catch (_) {}
    }
  }

  /// Decode barcodes from EMF file
  static Future<String?> decodeBarcodeFromEmf(String emfPath, {int dpi = 400}) async {
    if (!Platform.isWindows) return null;
    try {
      // Try multiple DPI values
      for (final d in [dpi, 300, 600, 200]) {
        final pngBytes = renderEmfToPng(emfPath, dpi: d);
        if (pngBytes == null) continue;
        final result = await _decodeFromBytes(pngBytes);
        if (result != null && result.isNotEmpty) return result;
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  /// Decode barcodes from EMF bytes
  static Future<String?> decodeBarcodeFromEmfBytes(Uint8List emfBytes, {int dpi = 400}) async {
    if (!Platform.isWindows) return null;
    try {
      final pngBytes = renderEmfBytesToPng(emfBytes, dpi: dpi);
      if (pngBytes == null) return null;
      for (final d in [dpi, 300, 600, 500]) {
        final png = d == dpi ? pngBytes : renderEmfBytesToPng(emfBytes, dpi: d);
        if (png == null) continue;
        final result = await _decodeFromBytes(png);
        if (result != null && result.isNotEmpty) return result;
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  static Future<String?> _decodeFromBytes(Uint8List bytes) async {
    try {
      // Try flutter_zxing
      final result = await zx.readBarcodeImagePathBytes(bytes);
      if (result.isValid && result.text.isNotEmpty) {
        return result.text;
      }
    } catch (_) {}

    try {
      // Try with image preprocessing
      final image = img.decodeImage(bytes);
      if (image == null) return null;
      
      // Try grayscale
      final gray = img.grayscale(image);
      final grayPng = img.encodePng(gray);
      try {
        final result = await zx.readBarcodeImagePathBytes(Uint8List.fromList(grayPng));
        if (result.isValid && result.text.isNotEmpty) return result.text;
      } catch (_) {}

      // Try threshold
      final thresh = img.Image(width: gray.width, height: gray.height);
      for (var y = 0; y < gray.height; y++) {
        for (var x = 0; x < gray.width; x++) {
          final p = gray.getPixel(x, y);
          final lum = img.getLuminance(p);
          if (lum > 128) {
            thresh.setPixelRgba(x, y, 255, 255, 255, 255);
          } else {
            thresh.setPixelRgba(x, y, 0, 0, 0, 255);
          }
        }
      }
      final threshPng = img.encodePng(thresh);
      try {
        final result = await zx.readBarcodeImagePathBytes(Uint8List.fromList(threshPng));
        if (result.isValid && result.text.isNotEmpty) return result.text;
      } catch (_) {}
    } catch (_) {}

    return null;
  }
}
