enum EditFormat {
  markdown('Markdown', '.md'),
  txt('TXT', '.txt'),
  pdf('PDF', '.pdf'),
  docx('DOCX', '.docx'),
  jwpub('JW', '.jwpub');

  final String label;
  final String extension;

  const EditFormat(this.label, this.extension);

  static EditFormat fromPath(String path) {
    final lowerPath = path.toLowerCase();
    if (lowerPath.endsWith('.md')) return EditFormat.markdown;
    if (lowerPath.endsWith('.pdf')) return EditFormat.pdf;
    if (lowerPath.endsWith('.docx')) return EditFormat.docx;
    if (lowerPath.endsWith('.jwpub')) return EditFormat.jwpub;
    return EditFormat.txt;
  }
}
