import 'package:flutter/material.dart';

class TextStyleController extends ChangeNotifier {
  // Current detected styles in selection (or global for plain text)
  double _fontSize = 16.0; 
  bool _isBold = false;
  bool _isItalic = false;

  double get fontSize => _fontSize;
  bool get isBold => _isBold;
  bool get isItalic => _isItalic;

  // Callbacks for applying styles (implemented by DocumentView)
  void Function(double size)? onApplyFontSize;
  VoidCallback? onToggleBold;
  VoidCallback? onToggleItalic;
  VoidCallback? onInsertDivider;
  VoidCallback? onToggleNote;

  // Update controller state from editor selection
  void updateFromSelection(double size, bool bold, bool italic) {
    if (_fontSize == size && _isBold == bold && _isItalic == italic) return;
    
    _fontSize = size;
    _isBold = bold;
    _isItalic = italic;
    notifyListeners();
  }

  // Action methods (called by toolbar)
  void incrementSize() {
    _fontSize += 1.0;
    notifyListeners();
    if (onApplyFontSize != null) {
      onApplyFontSize!(_fontSize);
    }
  }

  void decrementSize() {
    if (_fontSize > 1.0) {
      _fontSize -= 1.0;
      notifyListeners();
      if (onApplyFontSize != null) {
        onApplyFontSize!(_fontSize);
      }
    }
  }

  void setFontSize(double size) {
    _fontSize = size;
    notifyListeners();
    if (onApplyFontSize != null) {
      onApplyFontSize!(size);
    }
  }

  void toggleBold() {
    _isBold = !_isBold;
    notifyListeners();
    if (onToggleBold != null) {
      onToggleBold!();
    }
  }

  void toggleItalic() {
    _isItalic = !_isItalic;
    notifyListeners();
    if (onToggleItalic != null) {
      onToggleItalic!();
    }
  }

  void insertDivider() {
    if (onInsertDivider != null) {
      onInsertDivider!();
    }
  }

  void toggleNote() {
    notifyListeners();
    if (onToggleNote != null) {
      onToggleNote!();
    }
  }
}
