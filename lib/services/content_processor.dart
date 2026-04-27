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
    final htmlToConvert = mainContent?.innerHtml ?? document.body?.innerHtml ?? '';
    
    return _convertToMarkdown(htmlToConvert);
  }

  /// Converte um fragmento de HTML (como o da área de transferência) em Markdown.
  static String processHtmlFragment(String htmlFragment) {
    // Clipboard HTML often has headers, but the parser handles it.
    // We just want to ensure we get the body content.
    final document = html_parser.parse(htmlFragment);
    
    // Clean but be less aggressive than main content extraction
    _cleanDocument(document);
    
    final htmlToConvert = document.body?.innerHtml ?? '';
    return _convertToMarkdown(htmlToConvert);
  }

  static String _convertToMarkdown(String html) {
    if (html.trim().isEmpty) return '';
    
    return html2md.convert(
      html,
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
