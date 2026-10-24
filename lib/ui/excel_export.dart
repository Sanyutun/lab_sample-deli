import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

const String xlsxMimeType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Encodes [headers] + [rows] into an .xlsx workbook and returns the bytes.
Uint8List buildExcelBytes({
  required String sheetName,
  required List<String> headers,
  required List<List<Object?>> rows,
}) {
  final excel = Excel.createExcel();
  final defaultName = excel.getDefaultSheet() ?? 'Sheet1';
  if (defaultName != sheetName) {
    excel.rename(defaultName, sheetName);
  }
  final sheet = excel[sheetName];
  sheet.appendRow([for (final h in headers) TextCellValue(h)]);
  for (final row in rows) {
    sheet.appendRow([for (final cell in row) _cell(cell)]);
  }

  final encoded = excel.encode();
  if (encoded == null) {
    throw Exception('Could not build the Excel file.');
  }
  return Uint8List.fromList(encoded);
}

/// Builds an .xlsx workbook from [headers] + [rows] and opens the system
/// "save file" dialog. Returns true when the user saved the file, false if the
/// dialog was cancelled.
Future<bool> exportToExcel({
  required String fileName,
  required String sheetName,
  required List<String> headers,
  required List<List<Object?>> rows,
}) async {
  final bytes = buildExcelBytes(
    sheetName: sheetName,
    headers: headers,
    rows: rows,
  );
  final uri = await FilePicker.saveFile(
    dialogTitle: 'Save $fileName',
    fileName: fileName,
    bytes: bytes,
    mimeType: xlsxMimeType,
  );
  return uri != null;
}

CellValue? _cell(Object? value) {
  if (value == null) return null;
  if (value is int) return IntCellValue(value);
  if (value is num) return DoubleCellValue(value.toDouble());
  return TextCellValue(value.toString());
}
