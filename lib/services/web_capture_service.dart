import 'package:http/http.dart' as http;
import 'content_processor.dart';

class WebCaptureService {
  /// Captura o conteúdo de uma URL e retorna o Markdown correspondente.
  static Future<CaptureResult> captureUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (!uri.isAbsolute) {
        return CaptureResult.error('URL inválida. Certifique-se de incluir http:// ou https://');
      }

      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final markdown = ContentProcessor.processHtml(
          response.body,
          baseUrl: '${uri.scheme}://${uri.host}',
        );

        if (markdown.trim().isEmpty) {
          return CaptureResult.error('Não foi possível extrair conteúdo relevante desta página.');
        }

        return CaptureResult.success(markdown);
      } else {
        return CaptureResult.error('Erro ao acessar site: Status ${response.statusCode}');
      }
    } catch (e) {
      return CaptureResult.error('Falha na captura: $e');
    }
  }
}

class CaptureResult {
  final String? content;
  final String? errorMessage;
  final bool isSuccess;

  CaptureResult.success(this.content)
      : errorMessage = null,
        isSuccess = true;

  CaptureResult.error(this.errorMessage)
      : content = null,
        isSuccess = false;
}
