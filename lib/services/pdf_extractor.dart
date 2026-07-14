import 'dart:io';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Extracts plain text from a PDF selected by the admin.
/// Runs entirely on-device - Syncfusion's PDF library parses the file
/// locally, no server round-trip, no internet needed.
class PdfExtractor {
  static Future<String> extractText(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final document = PdfDocument(inputBytes: bytes);
    try {
      final extractor = PdfTextExtractor(document);
      return extractor.extractText();
    } finally {
      document.dispose();
    }
  }
}