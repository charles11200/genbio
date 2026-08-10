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

    // Collect and sort slide files so slide1, slide2, ... slide10 come out
    // in numeric order. A plain string sort would put "slide10" before
    // "slide2" (lexicographic '1' < '2'), scrambling extraction order for
    // any deck with 10+ slides, so sort by the parsed slide number instead.
    final slideNumber = RegExp(r'slide(\d+)\.xml$');
    final slideFiles = archive.files
        .where((f) =>
    f.isFile &&
        f.name.startsWith('ppt/slides/slide') &&
        slideNumber.hasMatch(f.name))
        .toList()
      ..sort((a, b) {
        final aNum = int.parse(slideNumber.firstMatch(a.name)!.group(1)!);
        final bNum = int.parse(slideNumber.firstMatch(b.name)!.group(1)!);
        return aNum.compareTo(bNum);
      });

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