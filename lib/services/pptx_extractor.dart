import 'dart:io';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// A .pptx file IS a zip archive containing one XML file per slide
/// (ppt/slides/slide1.xml, slide2.xml, ...). We don't need any heavy
/// Office-parsing library for this - `archive` unzips it and `xml` reads
/// the text run nodes directly. Fully offline, pure Dart, no plugin/native
/// code required.
class PptxExtractor {
  static Future<String> extractText(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final buffer = StringBuffer();

    // Collect and sort slide files so slide1, slide2... come out in order
    final slideFiles = archive.files
        .where((f) =>
    f.isFile &&
        f.name.startsWith('ppt/slides/slide') &&
        f.name.endsWith('.xml'))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    for (final file in slideFiles) {
      final xmlString = String.fromCharCodes(file.content as List<int>);
      buffer.writeln(_extractTextFromSlideXml(xmlString));
    }

    return buffer.toString();
  }

  static String _extractTextFromSlideXml(String xmlString) {
    final document = XmlDocument.parse(xmlString);
    // Text runs in slide XML are tagged <a:t>...</a:t>
    final textNodes = document.findAllElements('a:t');
    return textNodes.map((node) => node.innerText).join(' ');
  }
}