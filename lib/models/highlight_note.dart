import 'dart:ui';

enum HighlightType { text, pdf }

class HighlightNote {
  final String id;
  final String content;
  final String? highlightedText;
  final int colorValue;
  final HighlightType type;
  
  // For Text documents
  final int? startIndex;
  final int? endIndex;
  
  // For PDF documents
  final List<PdfRegion>? pdfRegions;
  
  final DateTime createdAt;

  HighlightNote({
    required this.id,
    required this.content,
    this.highlightedText,
    this.colorValue = 0x80FFFF00, // Semi-transparent yellow
    required this.type,
    this.startIndex,
    this.endIndex,
    this.pdfRegions,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'highlightedText': highlightedText,
      'colorValue': colorValue,
      'type': type.index,
      'startIndex': startIndex,
      'endIndex': endIndex,
      'pdfRegions': pdfRegions?.map((r) => {
        'pageNumber': r.pageNumber,
        'left': r.bounds.left,
        'top': r.bounds.top,
        'width': r.bounds.width,
        'height': r.bounds.height,
      }).toList(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory HighlightNote.fromJson(Map<String, dynamic> json) {
    return HighlightNote(
      id: json['id'],
      content: json['content'],
      highlightedText: json['highlightedText'],
      colorValue: json['colorValue'],
      type: HighlightType.values[json['type']],
      startIndex: json['startIndex'],
      endIndex: json['endIndex'],
      pdfRegions: (json['pdfRegions'] as List?)?.map((r) => PdfRegion(
        pageNumber: r['pageNumber'],
        bounds: Rect.fromLTWH(r['left'], r['top'], r['width'], r['height']),
      )).toList(),
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

class PdfRegion {
  final int pageNumber;
  final Rect bounds;

  PdfRegion({required this.pageNumber, required this.bounds});
}
