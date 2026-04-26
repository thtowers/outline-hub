import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

void main() {
  final details = PdfTextSelectionChangedDetails('test', Rect.zero);
  debugPrint('Properties: ${details.toString()}');
}
