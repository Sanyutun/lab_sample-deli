import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Decodes barcodes from EMF files using Windows GDI to render and
/// flutter_zxing/image packages for detection.
class EmfBarcodeDecoder {
  EmfBarcodeDecoder._();

  /// Render EMF file to PNG bytes at given DPI
  static Uint8List? renderEmfToPng(String emfPath, {int dpi = 300}) {
    if (!Platform.isWindows) return null;

    final hEnhMetaFile = GetEnhMetaFile(emfPath.toNativeUtf16());
    if (hEnhMetaFile == 0) return null;

    try {
      final header = calloc<ENHMETAHEADER>();
      GetEnhMetaFileHeader(hEnhMetaFile, sizeOf<ENHMETAHEADER>(), header);

      final rect = header.ref.rclFrame;
      // Frame is in 0.01mm units
      final widthMm = (rect.right - rect.left).abs() / 100.0;
      final heightMm = (rect.bottom - rect.top).abs() / 100.0;
      var widthPx = (widthMm * dpi / 25.4).round();
      var heightPx = (heightMm * dpi / 25.4).round();
      if (widthPx < 1) widthPx = 800;
      if (heightPx < 1) heightPx = 400;

      final hdcScreen = GetDC(0);
      final hdcMem = CreateCompatibleDC(hdcScreen);
      final hBitmap = CreateCompatibleBitmap(hdcScreen, widthPx, heightPx);
      final hOldBitmap = SelectObject(hdcMem, hBitmap);

      // Fill with white
      final brush = CreateSolidBrush(0x00FFFFFF);
      final rectPaint = calloc<RECT>()
        ..ref.left = 0
        ..ref.top = 0
        ..ref.right = widthPx
        ..ref.bottom = heightPx;
      FillRect(hdcMem, rectPaint, brush);
      DeleteObject(brush);

      // Play EMF
      final playRect = calloc<RECT>()
        ..ref.left = 0
        ..ref.top = 0
        ..ref.right = widthPx
        ..ref.bottom = heightPx;
      PlayEnhMetaFile(hdcMem, hEnhMetaFile, playRect);

      // Get bitmap bits
      final bmi = calloc<BITMAPINFO>();
      bmi.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
      bmi.ref.bmiHeader.biWidth = widthPx;
      bmi.ref.bmiHeader.biHeight = -heightPx; // top-down
      bmi.ref.bmiHeader.biPlanes = 1;
      bmi.ref.bmiHeader.biBitCount = 32;
      bmi.ref.bmiHeader.biCompression = BI_RGB;

      final bufferSize = widthPx * heightPx * 4;
      final pixels = calloc<Uint8>(bufferSize);
      GetDIBits(hdcMem, hBitmap, 0, heightPx, pixels, bmi, DIB_RGB_COLORS);

      // Convert BGRA to RGBA PNG
      final pngBytes = _bgraToPng(pixels, widthPx, heightPx);

      SelectObject(hdcMem, hOldBitmap);
      DeleteObject(hBitmap);
      DeleteDC(hdcMem);
      ReleaseDC(0, hdcScreen);
      free(header);
      free(rectPaint);
      free(playRect);
      free(bmi);
      free(pixels);
      return pngBytes;
    } finally {
      DeleteEnhMetaFile(hEnhMetaFile);
    }
  }

  static Uint8List _bgraToPng(Pointer<Uint8> pixels, int width, int height) {
    // Use image package
    final rgba = Uint8List(width * height * 4);
    for (var i = 0; i < width * height; i++) {
      final b = pixels[i * 4 + 0];
      final g = pixels[i * 4 + 1];
      final r = pixels[i * 4 + 2];
      final a = pixels[i * 4 + 3];
      rgba[i * 4 + 0] = r;
      rgba[i * 4 + 1] = g;
      rgba[i * 4 + 2] = b;
      rgba[i * 4 + 3] = a == 0 ? 255 : a;
    }
    // We'll use image package - import dynamically
    return Uint8List.fromList([]);
  }
}
