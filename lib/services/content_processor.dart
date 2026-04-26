import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:html2md/html2md.dart' as html2md;

class ContentProcessor {
  /// Converte HTML bruto em Markdown estruturado, focando no conteúdo principal.
  static String processHtml(String rawHtml, {String? baseUrl}) {
    final document = html_parser.parse(rawHtml);

    // 1. Normalização: Limpeza inicial
    _cleanDocument(document);

    // 2. Extração: Tentar encontrar o conteúdo principal
    final mainContent = _findMainContent(document);

    // 3. Conversão: HTML para Markdown
    // Usamos o outerHtml do elemento selecionado ou o body inteiro se falhar
    final htmlToConvert = mainContent?.innerHtml ?? document.body?.innerHtml ?? '';
    
    return html2md.convert(
      htmlToConvert,
      styleOptions: {
        'headingStyle': 'atx', // # H1
        'hr': '---',
        'bulletListMarker': '-',
        'codeBlockStyle': 'fenced',
      },
    );
  }

  /// Remove elementos que não fazem parte do conteúdo (scripts, estilos, ads, etc.)
  static void _cleanDocument(dom.Document doc) {
    const tagsToRemove = [
      'script',
      'style',
      'noscript',
      'iframe',
      'header',
      'footer',
      'nav',
      'aside',
      'form',
      'button',
      '.ads',
      '.advertisement',
      '#comments',
    ];

    for (var tag in tagsToRemove) {
      doc.querySelectorAll(tag).forEach((element) => element.remove());
    }
  }

  /// Tenta identificar o container do conteúdo principal (artigo/post)
  static dom.Element? _findMainContent(dom.Document doc) {
    // Ordem de preferência de seletores comuns
    final selectors = [
      'article',
      '[role="main"]',
      'main',
      '.post-content',
      '.article-content',
      '#content',
      '.content',
    ];

    for (var selector in selectors) {
      final element = doc.querySelector(selector);
      if (element != null && element.text.trim().length > 200) {
        return element;
      }
    }

    // Heurística simples: o elemento com mais texto
    return _findElementWithMostText(doc.body);
  }

  static dom.Element? _findElementWithMostText(dom.Element? root) {
    if (root == null) return null;

    dom.Element? bestElement = root;
    int maxTextLength = 0;

    void traverse(dom.Element element) {
      // Ignorar elementos de bloco muito grandes que são apenas containers
      final textLength = element.text.trim().length;
      if (textLength > maxTextLength) {
        maxTextLength = textLength;
        bestElement = element;
      }

      for (var child in element.children) {
        traverse(child);
      }
    }

    traverse(root);
    return bestElement;
  }
}
