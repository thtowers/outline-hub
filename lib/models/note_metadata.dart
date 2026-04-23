class NoteMetadata {
  String title;
  String description;

  NoteMetadata({this.title = '', this.description = ''});

  NoteMetadata copyWith({String? title, String? description}) {
    return NoteMetadata(
      title: title ?? this.title,
      description: description ?? this.description,
    );
  }
}
