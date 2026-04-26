import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:docx_creator/docx_creator.dart';
import 'package:xml/xml.dart';

class DocxService {
  /// Extrai o texto de um arquivo .docx
  static String extractText(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final documentFile = archive.findFile('word/document.xml');
      if (documentFile == null) return '';

      final content = utf8.decode(documentFile.content as List<int>);
      final document = XmlDocument.parse(content);

      // Encontrar todos os parágrafos <w:p>
      final paragraphs = document.findAllElements('w:p');
      final sb = StringBuffer();

      for (var p in paragraphs) {
        // Para cada parágrafo, encontrar todos os textos <w:t>
        final textElements = p.findAllElements('w:t');
        for (var t in textElements) {
          sb.write(t.innerText);
        }
        sb.writeln(); // Nova linha após cada parágrafo
      }

      return sb.toString().trim();
    } catch (e) {
      return 'Erro ao ler DOCX: $e';
    }
  }

  /// Salva um conteúdo Markdown como arquivo .docx
  static Future<void> saveAsDocx(String path, String markdown) async {
    // Usamos o builder fluente da biblioteca docx_creator
    final builder = docx();
    
    final lines = markdown.split('\n');
    
    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      
      // Detecção simples de cabeçalhos Markdown
      if (trimmed.startsWith('# ')) {
        builder.h1(trimmed.substring(2));
      } else if (trimmed.startsWith('## ')) {
        builder.h2(trimmed.substring(3));
      } else if (trimmed.startsWith('### ')) {
        builder.h3(trimmed.substring(4));
      } else {
        builder.p(line);
      }
    }

    final doc = builder.build();
    // DocxExporter é a classe responsável por gerar o arquivo físico
    await DocxExporter().exportToFile(doc, path);
  }
}
