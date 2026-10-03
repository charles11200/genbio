import 'dart:io';

import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Below this many non-whitespace characters, a page is treated as having
/// no real digital text layer - either genuinely blank or (far more often
/// in practice) a scanned/photographed page a phone scanner app exported
/// as an image with no text underneath, which PdfTextExtractor can't read
/// since it only sees existing text layers, never pixels.
const int _minDigitalTextCharsPerPage = 20;

/// Extracts plain text from a PDF selected by the student.
///
/// Two tiers, both fully offline:
/// 1. Syncfusion's [PdfTextExtractor] reads each page's existing text
///    layer - fast, and all that's needed for a PDF exported from
///    Word/PPT/Google Docs.
/// 2. Any page whose text layer comes back near-empty is assumed to be a
///    scanned/photographed page (e.g. from a phone scanner app like
///    TapScanner) with no text layer at all. That page is rasterized with
///    pdfx (Android's native PdfRenderer) and re-read with Tesseract OCR
///    instead - see [extractTextWithOcrFallback].
class PdfExtractor {
  /// Fast path only - the original text-layer-only behavior. Kept for
  /// anywhere that just wants whatever digital text already exists without
  /// paying for OCR (e.g. a quick density check).
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

  /// Full pipeline: digital text layer per page, OCR fallback for any page
  /// that doesn't have one. [onOcrPage] fires with (page, totalPages) each
  /// time a page needs the OCR fallback, so a caller can show progress -
  /// a normal, fully-digital PDF never triggers it at all.
  ///
  /// Must run on the main isolate, not inside `compute()` - both pdfx and
  /// flutter_tesseract_ocr are native plugins that talk to Android over a
  /// platform channel, which a `compute()`-spawned background isolate
  /// doesn't have (same constraint documented on TermEmbeddingService's
  /// TFLite calls).
  static Future<String> extractTextWithOcrFallback(
    String filePath, {
    void Function(int page, int totalPages)? onOcrPage,
  }) async {
    final bytes = await File(filePath).readAsBytes();
    final document = PdfDocument(inputBytes: bytes);
    final pageCount = document.pages.count;
    final extractor = PdfTextExtractor(document);

    final buffer = StringBuffer();
    pdfx.PdfDocument? renderDoc;
    try {
      for (var i = 0; i < pageCount; i++) {
        final pageText = extractor.extractText(
          startPageIndex: i,
          endPageIndex: i,
        );
        if (_nonWhitespaceLength(pageText) >= _minDigitalTextCharsPerPage) {
          buffer.writeln(pageText);
          continue;
        }

        onOcrPage?.call(i + 1, pageCount);
        renderDoc ??= await pdfx.PdfDocument.openFile(filePath);
        final ocrText = await _ocrPage(renderDoc, i + 1);
        buffer.writeln(ocrText.trim().isNotEmpty ? ocrText : pageText);
      }
    } finally {
      document.dispose();
      await renderDoc?.close();
    }
    return buffer.toString();
  }

  static Future<String> _ocrPage(
    pdfx.PdfDocument renderDoc,
    int pageNumber,
  ) async {
    final page = await renderDoc.getPage(pageNumber);
    try {
      // 2x page size gives Tesseract enough resolution to read normal body
      // text reliably without ballooning memory/time on very large pages.
      final rendered = await page.render(
        width: page.width * 2,
        height: page.height * 2,
        format: pdfx.PdfPageImageFormat.png,
      );
      if (rendered == null) return '';

      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/ocr_page_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await tempFile.writeAsBytes(rendered.bytes);
      try {
        return await FlutterTesseractOcr.extractText(
          tempFile.path,
          language: 'eng',
          args: const {'preserve_interword_spaces': '1'},
        );
      } finally {
        if (await tempFile.exists()) await tempFile.delete();
      }
    } finally {
      await page.close();
    }
  }

  static int _nonWhitespaceLength(String text) =>
      text.replaceAll(RegExp(r'\s'), '').length;
}
