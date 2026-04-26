import 'highlight_note.dart';

class NoteMetadata {
  String title;
  String description;
  int colorValue;
  List<HighlightNote> highlights;

  NoteMetadata({
    this.title = '',
    this.description = '',
    this.colorValue = 0xFFFBC02D, // Default yellow
    List<HighlightNote>? highlights,
  }) : highlights = highlights ?? [];

  NoteMetadata copyWith({
    String? title,
    String? description,
    int? colorValue,
    List<HighlightNote>? highlights,
  }) {
    return NoteMetadata(
      title: title ?? this.title,
      description: description ?? this.description,
      colorValue: colorValue ?? this.colorValue,
      highlights: highlights ?? this.highlights,
    );
  }
}
