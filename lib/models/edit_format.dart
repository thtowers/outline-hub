enum EditFormat {
  markdown('Markdown', '.md'),
  txt('Texto Simples', '.txt');

  final String label;
  final String extension;

  const EditFormat(this.label, this.extension);

  static EditFormat fromPath(String path) {
    final ext = path.split('.').last.toLowerCase();
    if (ext == 'md') return EditFormat.markdown;
    return EditFormat.txt;
  }
}
