import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:docx_to_text/docx_to_text.dart';
import 'dart:convert';
import '../theme/app_theme.dart';
import 'dart:io';
import '../models/edit_format.dart';
import '../models/note_metadata.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

class DocumentView extends StatefulWidget {
  final List<String> tabs;
  final int activeTabIndex;
  final Map<String, String> fileContents;
  final Function(int) onCloseTab;
  final Function(int) onSelectTab;
  final void Function(int, int) onReorderTab;
  final VoidCallback onNewTab;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenFolder;
  final VoidCallback onSaveFile;
  final Function(String, String) onContentChanged;
  final int tabWidth;
  final bool autoIndent;
  final bool insertSpaces;
  final EditFormat? currentFormat;
  final Map<String, NoteMetadata> noteMetadataMap;
  final Function(String, NoteMetadata) onMetadataChanged;
  final void Function(int line, int column)? onPositionChanged;

  const DocumentView({
    super.key,
    required this.tabs,
    required this.activeTabIndex,
    required this.fileContents,
    required this.onCloseTab,
    required this.onSelectTab,
    required this.onReorderTab,
    required this.onNewTab,
    required this.onOpenFile,
    required this.onOpenFolder,
    required this.onSaveFile,
    required this.onContentChanged,
    required this.tabWidth,
    required this.autoIndent,
    required this.insertSpaces,
    required this.noteMetadataMap,
    required this.onMetadataChanged,
    this.onPositionChanged,
    this.currentFormat,
  });

  @override
  State<DocumentView> createState() => _DocumentViewState();
}

class _DocumentViewState extends State<DocumentView> {
  // For plain text / non-markdown files
  late TextEditingController _plainTextController;
  late FocusNode _plainTextFocusNode;

  // For markdown files – AppFlowy editor
  EditorState? _editorState;
  StreamSubscription<EditorTransactionValue>? _editorSubscription;
  String? _lastLoadedMarkdownPath;

  // For note header (title + description)
  late TextEditingController _titleController;
  late TextEditingController _descController;

  @override
  void initState() {
    super.initState();
    _plainTextController = TextEditingController();
    _plainTextController.addListener(() {
      if (widget.tabs.isNotEmpty && widget.activeTabIndex < widget.tabs.length) {
        final path = widget.tabs[widget.activeTabIndex];
        widget.onContentChanged(path, _plainTextController.text);
        
        // Update Line and Column
        if (widget.onPositionChanged != null) {
          final selection = _plainTextController.selection;
          if (selection.isValid) {
            final textBefore = _plainTextController.text.substring(0, selection.baseOffset);
            final lines = textBefore.split('\n');
            widget.onPositionChanged!(lines.length, lines.last.length + 1);
          }
        }
      }
    });
    _plainTextFocusNode = FocusNode();
    _titleController = TextEditingController();
    _descController = TextEditingController();
    _loadCurrentTab();
  }

  bool get _isMarkdown {
    if (widget.tabs.isEmpty) return false;
    final path = widget.tabs[widget.activeTabIndex];
    final isMd = path.toLowerCase().endsWith('.md') ||
        widget.currentFormat == EditFormat.markdown;
    debugPrint('DocumentView: _isMarkdown for $path = $isMd (format: ${widget.currentFormat})');
    return isMd;
  }

  String _getContentForCurrentTab() {
    if (widget.tabs.isEmpty) return '';
    final path = widget.tabs[widget.activeTabIndex];

    if (widget.fileContents.containsKey(path)) return widget.fileContents[path]!;

    try {
      if (path.toLowerCase().endsWith('.jwpub') ||
          path.toLowerCase().endsWith('.pdf') ||
          path.toLowerCase().endsWith('.docx')) {
        return '';
      }
      final file = File(path);
      if (file.existsSync()) return file.readAsStringSync();
      return '';
    } catch (e) {
      return '';
    }
  }

  void _loadCurrentTab() {
    final content = _getContentForCurrentTab();
    debugPrint('DocumentView: Loading tab. isMarkdown=$_isMarkdown, content length=${content.length}');
    if (_isMarkdown) {
      _loadMarkdownEditor(content);
    } else {
      setState(() {
        _plainTextController.text = content;
        _editorState = null;
      });
    }
  }

  void _loadMarkdownEditor(String markdownContent) {
    final path =
        widget.tabs.isNotEmpty ? widget.tabs[widget.activeTabIndex] : '';
    
    debugPrint('DocumentView: Loading Markdown editor for path: $path');
    
    if (_lastLoadedMarkdownPath == path && _editorState != null) {
      debugPrint('DocumentView: Editor already loaded for this path, skipping.');
      return;
    }

    _editorSubscription?.cancel();
    _editorSubscription = null;

    _lastLoadedMarkdownPath = path;

    try {
      final Document document;
      if (markdownContent.trim().isEmpty) {
        debugPrint('DocumentView: Creating blank document.');
        document = Document.blank(withInitialText: true);
      } else {
        document = markdownToDocument(markdownContent);
      }
      
      setState(() {
        _editorState = EditorState(document: document);
        debugPrint('DocumentView: EditorState initialized.');
      });

      // Listen to transaction stream for changes
      _editorSubscription = _editorState!.transactionStream.listen((value) {
        final (time, transaction, options) = value;
        if (time == TransactionTime.after) {
          if (!mounted) return;
          if (widget.tabs.isEmpty) return;
          final currentPath = widget.tabs[widget.activeTabIndex];
          final markdown = documentToMarkdown(_editorState!.document);
          widget.onContentChanged(currentPath, markdown);
        }
      });

      // Selection listener for Line/Col
      _editorState!.selectionNotifier.addListener(() {
        if (widget.onPositionChanged != null) {
          final selection = _editorState!.selection;
          if (selection != null) {
            int lineIndex = 0;
            
            final currentPath = selection.start.path;
            if (currentPath.isNotEmpty) {
              lineIndex = currentPath.first + 1;
            }
            
            widget.onPositionChanged!(lineIndex, selection.start.offset + 1);
          }
        }
      });
    } catch (e, stack) {
      debugPrint('DocumentView: Error loading markdown: $e');
      debugPrint(stack.toString());
      // Fallback to plain text if markdown loading fails
      setState(() {
        _editorState = null;
        _plainTextController.text = markdownContent;
      });
    }
  }

  @override
  void didUpdateWidget(DocumentView oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldPath = oldWidget.tabs.isNotEmpty &&
            oldWidget.activeTabIndex < oldWidget.tabs.length
        ? oldWidget.tabs[oldWidget.activeTabIndex]
        : null;
    final newPath = widget.tabs.isNotEmpty &&
            widget.activeTabIndex < widget.tabs.length
        ? widget.tabs[widget.activeTabIndex]
        : null;

    final tabChanged = oldPath != newPath ||
        oldWidget.tabs.length != widget.tabs.length ||
        oldWidget.currentFormat != widget.currentFormat;

    debugPrint('DocumentView: didUpdateWidget. tabChanged=$tabChanged (oldPath=$oldPath, newPath=$newPath, oldFormat=${oldWidget.currentFormat}, newFormat=${widget.currentFormat})');

    if (tabChanged) {
      _editorSubscription?.cancel();
      _editorSubscription = null;
      _editorState = null;
      _lastLoadedMarkdownPath = null;
      _loadCurrentTab();
      // Update header controllers for new tab
      final newPath = widget.tabs.isNotEmpty &&
              widget.activeTabIndex < widget.tabs.length
          ? widget.tabs[widget.activeTabIndex]
          : null;
      if (newPath != null) {
        final meta = widget.noteMetadataMap[newPath] ?? NoteMetadata();
        _titleController.text = meta.title;
        _descController.text = meta.description;
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    _plainTextController.dispose();
    _plainTextFocusNode.dispose();
    _titleController.dispose();
    _descController.dispose();
    _editorSubscription?.cancel();
    super.dispose();
  }

  IconData _getFileIcon(String filename) {
    if (filename.endsWith('.dart')) return Icons.flutter_dash;
    if (filename.endsWith('.js')) return Icons.javascript;
    if (filename.endsWith('.html')) return Icons.html;
    if (filename.endsWith('.css')) return Icons.css;
    if (filename.endsWith('.md')) return Icons.description;
    if (filename.endsWith('.json')) return Icons.settings;
    if (filename.endsWith('.txt')) return Icons.text_snippet;
    if (filename.endsWith('.jwpub')) return Icons.library_books;
    if (filename.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (filename.endsWith('.docx')) return Icons.description;
    return Icons.insert_drive_file;
  }

  bool _isJwPub(String path) => path.toLowerCase().endsWith('.jwpub');
  bool _isPdf(String path) => path.toLowerCase().endsWith('.pdf');
  bool _isDocx(String path) => path.toLowerCase().endsWith('.docx');

  Widget _buildPdfView(String path) => PdfViewer.file(path);

  Widget _buildDocxView(String path) {
    return FutureBuilder<String>(
      future: _loadDocxText(path),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
              child: Text('Error loading DOCX: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red)));
        }
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: SingleChildScrollView(
            child: Text(snapshot.data ?? '',
                style: AppTheme.codeTextStyle.copyWith(fontSize: 14)),
          ),
        );
      },
    );
  }

  Future<String> _loadDocxText(String path) async {
    final bytes = await File(path).readAsBytes();
    return docxToText(bytes);
  }

  Widget _buildPublicationView(String path) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadJwPubData(path),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: Text('Error loading publication: ${snapshot.error}',
                style: TextStyle(color: Colors.red.shade300)),
          );
        }
        final data = snapshot.data!;
        final manifest = data['manifest'] as Map<String, dynamic>;
        final documents = data['documents'] as List<Map<String, dynamic>>;
        final pub = manifest['publication'] ?? {};
        final title =
            pub['title'] ?? pub['displayTitle'] ?? 'Unknown Publication';

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: AppTheme.accent.withValues(alpha: 0.05),
              child: Row(children: [
                Icon(Icons.library_books, color: AppTheme.accent, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ),
                Text(pub['symbol'] ?? '',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: documents.length,
                itemBuilder: (context, index) {
                  final doc = documents[index];
                  return Card(
                    color: AppTheme.surface,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                          color: AppTheme.textSecondary.withValues(alpha: 0.1)),
                    ),
                    margin: const EdgeInsets.only(bottom: 16),
                    child: ExpansionTile(
                      initiallyExpanded: index == 0,
                      title: Text(doc['Title'] ?? 'No Title',
                          style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600)),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(doc['Content'] ?? '',
                              style:
                                  AppTheme.codeTextStyle.copyWith(fontSize: 13)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, dynamic>> _loadJwPubData(String path) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final manifestFile = archive.findFile('manifest.json');
    if (manifestFile == null) throw Exception('manifest.json not found');
    final manifest =
        json.decode(utf8.decode(manifestFile.content as List<int>));

    final contentsFile = archive.findFile('contents');
    if (contentsFile == null) throw Exception('contents file not found');

    final contentsArchive =
        ZipDecoder().decodeBytes(contentsFile.content as List<int>);
    final dbFile =
        contentsArchive.files.firstWhere((f) => f.name.endsWith('.db'));

    final tempDir = await getTemporaryDirectory();
    final dbPath = p.join(tempDir.path, dbFile.name);
    await File(dbPath).writeAsBytes(dbFile.content as List<int>);

    final Database db = await openDatabase(dbPath, readOnly: true);
    List<Map<String, dynamic>> documents = [];

    try {
      final docMaps = await db.query('Document',
          columns: ['DocumentId', 'Title', 'Content']);

      for (var docMap in docMaps) {
        final docId = docMap['DocumentId'] as int;
        final title = (docMap['Title'] as String?) ?? 'No Title';
        String contentText = '';

        try {
          final columns =
              await db.rawQuery('PRAGMA table_info(DocumentParagraph)');
          String? targetColumn;
          for (var col in columns) {
            final name = col['name'].toString().toLowerCase();
            if (name == 'content' || name == 'text' || name == 'markup') {
              targetColumn = col['name'].toString();
              break;
            }
          }
          if (targetColumn != null) {
            final paraMaps = await db.query('DocumentParagraph',
                columns: [targetColumn],
                where: 'DocumentId = ?',
                whereArgs: [docId]);
            if (paraMaps.isNotEmpty) {
              contentText = paraMaps
                  .map((p) => p[targetColumn]?.toString() ?? '')
                  .join('\n\n');
            }
          }
        } catch (_) {}

        if (contentText.isEmpty) {
          try {
            final unitMaps = await db.query('TextUnit',
                columns: ['Text'],
                where: 'DocumentId = ?',
                whereArgs: [docId]);
            if (unitMaps.isNotEmpty) {
              contentText =
                  unitMaps.map((u) => u['Text']?.toString() ?? '').join('\n\n');
            }
          } catch (_) {}
        }

        if (contentText.isEmpty) {
          final blob = docMap['Content'];
          if (blob is List<int> && blob.isNotEmpty) {
            contentText = _decodeBlob(blob);
          } else if (blob is String) {
            contentText = blob;
          }
        }

        contentText = contentText.replaceAll(RegExp(r'<[^>]*>'), '');
        contentText = contentText.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

        if (contentText.isNotEmpty) {
          documents.add({'Title': title, 'Content': contentText});
        }
      }
    } catch (e) {
      debugPrint('Error querying Document table: $e');
    }

    await db.close();
    if (documents.isEmpty) throw Exception('Could not find any readable text.');
    return {'manifest': manifest, 'documents': documents};
  }

  String _decodeBlob(List<int> blob) {
    try {
      return utf8.decode(ZLibDecoder().decodeBytes(blob));
    } catch (_) {}
    try {
      return utf8.decode(GZipDecoder().decodeBytes(blob));
    } catch (_) {}
    try {
      return utf8.decode(Inflate(blob).getBytes());
    } catch (_) {}
    try {
      return utf8.decode(blob);
    } catch (_) {}
    return '[Binary Content: ${blob.length} bytes]';
  }

  // ─── MARKDOWN EDITOR ─────────────────────────────────────────────────────

  Widget _buildMarkdownEditor() {
    if (_editorState == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Modern style for AppFlowy v6.2.0
    final editorStyle = EditorStyle.desktop(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
      cursorColor: AppTheme.accent,
      selectionColor: AppTheme.accent.withValues(alpha: 0.3),
      textStyleConfiguration: TextStyleConfiguration(
        text: AppTheme.codeTextStyle.copyWith(
          fontSize: 15,
          height: 1.5,
          color: AppTheme.textPrimary,
        ),
        bold: const TextStyle(fontWeight: FontWeight.bold),
        italic: const TextStyle(fontStyle: FontStyle.italic),
        underline: const TextStyle(decoration: TextDecoration.underline),
        strikethrough: const TextStyle(decoration: TextDecoration.lineThrough),
        href: TextStyle(
          color: AppTheme.accent,
          decoration: TextDecoration.underline,
        ),
        code: AppTheme.codeTextStyle.copyWith(
          fontSize: 13,
          backgroundColor: AppTheme.surface,
          color: const Color(0xFFE06C75),
        ),
        lineHeight: 1.5,
      ),
    );

    final path =
        widget.tabs.isNotEmpty ? widget.tabs[widget.activeTabIndex] : '';
    final metadata = widget.noteMetadataMap[path] ?? NoteMetadata();

    // Custom Enter key behavior:
    // - Enter: insert soft newline (\n) in the same block with auto-indent
    // - Shift + Enter: original behavior (create new block)
    final customInsertNewLine = CharacterShortcutEvent(
      key: 'custom_soft_newline',
      character: '\n',
      handler: (editorState) async {
        final selection = editorState.selection?.normalized;
        if (selection == null) return false;

        if (HardwareKeyboard.instance.isShiftPressed) {
          // Shift + Enter -> original "insertNewLine" (new block)
          await editorState.deleteSelection(selection);
          await editorState.insertNewLine(position: selection.start);
          return true;
        }

        // Enter only -> insert \n character in same block with auto-indent
        if (!selection.isCollapsed) {
          await editorState.deleteSelection(selection);
        }

        final node = editorState.getNodeAtPath(selection.start.path);
        final delta = node?.delta;
        String insertString = '\n';

        if (widget.autoIndent && delta != null) {
          final text = delta.toPlainText();
          final offset = selection.start.offset;
          int lineStart = text.lastIndexOf('\n', offset - 1) + 1;
          if (lineStart < 0) lineStart = 0;
          final currentLine = text.substring(lineStart, offset);
          final match = RegExp(r'^\s*').firstMatch(currentLine);
          final indentation = match?.group(0) ?? '';
          insertString += indentation;
        }

        await editorState.insertTextAtCurrentSelection(insertString);
        return true;
      },
    );

    final customTabCommand = CommandShortcutEvent(
      key: 'custom_tab',
      command: 'tab',
      handler: (editorState) {
        final selection = editorState.selection;
        if (selection == null) return KeyEventResult.ignored;

        final node = editorState.getNodeAtPath(selection.start.path);
        if (node == null) return KeyEventResult.ignored;

        // If at the beginning of a list item, try block indentation
        final isList = node.type == BulletedListBlockKeys.type ||
            node.type == NumberedListBlockKeys.type ||
            node.type == TodoListBlockKeys.type;

        if (isList && selection.start.offset == 0) {
          final result = indentCommand.handler(editorState);
          if (result == KeyEventResult.handled) {
            return result;
          }
        }

        // Otherwise, insert spaces or tab character (synchronous)
        final tabString = widget.insertSpaces ? ' ' * widget.tabWidth : '\t';
        final transaction = editorState.transaction;
        transaction.insertText(node, selection.start.offset, tabString);
        transaction.afterSelection = Selection.collapsed(
          Position(
            path: selection.start.path,
            offset: selection.start.offset + tabString.length,
          ),
        );
        editorState.apply(transaction);

        return KeyEventResult.handled;
      },
      getDescription: () => 'Insert tab or spaces',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildNoteHeader(path, metadata),
        Expanded(
          child: AppFlowyEditor(
            editorState: _editorState!,
            editorStyle: editorStyle,
            autoFocus: false,
            editable: true,
            characterShortcutEvents: [
              customInsertNewLine,
              ...standardCharacterShortcutEvents
                  .where((e) => e.character != '\n'),
            ],
            commandShortcutEvents: [
              customTabCommand,
              ...standardCommandShortcutEvents.where((e) => e.key != 'indent'),
            ],
          ),
        ),
      ],
    );
  }

  // ─── NOTE HEADER (title + description) ────────────────────────────────────

  Widget _buildNoteHeader(String path, NoteMetadata metadata) {
    return Container(
      padding: const EdgeInsets.fromLTRB(48, 32, 48, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tema / Título da nota
          TextField(
            controller: _titleController,
            onChanged: (val) {
              widget.onMetadataChanged(
                path,
                metadata.copyWith(title: val),
              );
            },
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
            decoration: InputDecoration(
              hintText: 'Título da nota...',
              hintStyle: TextStyle(
                color: AppTheme.textSecondary.withValues(alpha: 0.4),
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            maxLines: 1,
          ),
          const SizedBox(height: 8),
          // Descrição livre
          TextField(
            controller: _descController,
            onChanged: (val) {
              widget.onMetadataChanged(
                path,
                metadata.copyWith(description: val),
              );
            },
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
            decoration: InputDecoration(
              hintText: 'Adicione uma descrição...',
              hintStyle: TextStyle(
                color: AppTheme.textSecondary.withValues(alpha: 0.3),
                fontSize: 14,
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            maxLines: null,
          ),
          const SizedBox(height: 16),
          Divider(
            height: 1,
            color: AppTheme.textSecondary.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ─── PLAIN TEXT EDITOR ───────────────────────────────────────────────────

  Widget _buildPlainTextEditor() {
    return Padding(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 16),
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.tab) {
              _handleTabKey();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.enter &&
                widget.autoIndent) {
              _handleEnterKey();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
          controller: _plainTextController,
          focusNode: _plainTextFocusNode,
          onChanged: (text) {
            if (widget.tabs.isNotEmpty &&
                widget.activeTabIndex < widget.tabs.length) {
              widget.onContentChanged(
                  widget.tabs[widget.activeTabIndex], text);
            }
          },
          maxLines: null,
          expands: true,
          style: AppTheme.codeTextStyle,
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
          keyboardType: TextInputType.multiline,
          textAlignVertical: TextAlignVertical.top,
        ),
      ),
    );
  }

  // ─── MAIN BUILD ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.background,
      child: Column(
        children: [
          _buildTabs(),
          const Divider(height: 1),
          Expanded(
            child: widget.tabs.isEmpty
                ? _buildEmptyState()
                : _isJwPub(widget.tabs[widget.activeTabIndex])
                    ? _buildPublicationView(widget.tabs[widget.activeTabIndex])
                    : _isPdf(widget.tabs[widget.activeTabIndex])
                        ? _buildPdfView(widget.tabs[widget.activeTabIndex])
                        : _isDocx(widget.tabs[widget.activeTabIndex])
                            ? _buildDocxView(
                                widget.tabs[widget.activeTabIndex])
                            : _isMarkdown
                                ? _buildMarkdownEditor()
                                : _buildPlainTextEditor(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      color: AppTheme.background,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo/Hero Icon
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.edit_note_rounded,
                  size: 80,
                  color: AppTheme.accent,
                ),
              ),
              const SizedBox(height: 32),

              // Welcome Text
              Text(
                'Outline Hub',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Organize suas ideias e anotações com simplicidade.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 48),

              // Action Grid/Wrap
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildWelcomeActionCard(
                      icon: Icons.add_rounded,
                      title: 'Nova Anotação',
                      description: 'Comece a escrever uma nota do zero',
                      onTap: widget.onNewTab,
                    ),
                    _buildWelcomeActionCard(
                      icon: Icons.file_open_rounded,
                      title: 'Abrir Arquivo',
                      description: 'Carregue um arquivo .md ou .txt existente',
                      onTap: widget.onOpenFile,
                    ),
                    _buildWelcomeActionCard(
                      icon: Icons.folder_open_rounded,
                      title: 'Abrir Pasta',
                      description: 'Selecione um diretório para trabalhar',
                      onTap: widget.onOpenFolder,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 64),

              // Tips or Footer
              Text(
                'Dica: Use a barra superior para alternar entre Markdown e Texto Simples',
                style: TextStyle(
                  color: AppTheme.textSecondary.withValues(alpha: 0.4),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeActionCard({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 170,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.textSecondary.withValues(alpha: 0.1),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: AppTheme.accent),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      height: 36,
      color: AppTheme.surface,
      child: Row(
        children: [
          Expanded(
            child: Theme(
              data: Theme.of(context).copyWith(
                canvasColor: Colors.transparent,
                shadowColor: Colors.transparent,
              ),
              child: ReorderableListView(
                scrollDirection: Axis.horizontal,
                onReorder: widget.onReorderTab,
                buildDefaultDragHandles: false,
                proxyDecorator: (child, index, animation) =>
                    Material(color: Colors.transparent, child: child),
                children: List.generate(widget.tabs.length, (index) {
                  final isSelected = widget.activeTabIndex == index;
                  final path = widget.tabs[index];
                  final filename = path.split('/').last;

                  return ReorderableDragStartListener(
                    key: ValueKey(path),
                    index: index,
                    child: InkWell(
                      onTap: () => widget.onSelectTab(index),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.background
                              : Colors.transparent,
                          border: isSelected
                              ? Border(
                                  bottom: BorderSide(
                                      color: AppTheme.accent, width: 2))
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(_getFileIcon(filename),
                                size: 14,
                                color: isSelected
                                    ? AppTheme.accent
                                    : AppTheme.textSecondary),
                            const SizedBox(width: 8),
                            Text(filename,
                                style: TextStyle(
                                  color: isSelected
                                      ? AppTheme.textPrimary
                                      : AppTheme.textSecondary,
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                )),
                            const SizedBox(width: 8),
                            Tooltip(
                              message: 'Fechar Aba',
                              child: InkWell(
                                onTap: () => widget.onCloseTab(index),
                                child: Icon(Icons.close,
                                    size: 14,
                                    color: AppTheme.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: IconButton(
              icon: const Icon(Icons.add, size: 18),
              onPressed: widget.onNewTab,
              tooltip: 'Nova Aba',
              splashRadius: 18,
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ),
        ],
      ),
    );
  }

  void _handleTabKey() {
    final text = _plainTextController.text;
    final selection = _plainTextController.selection;
    final tabString = widget.insertSpaces ? ' ' * widget.tabWidth : '\t';
    final newText =
        text.replaceRange(selection.start, selection.end, tabString);
    final newSelection = TextSelection.collapsed(
        offset: selection.start + tabString.length);
    _plainTextController.value =
        TextEditingValue(text: newText, selection: newSelection);
    if (widget.tabs.isNotEmpty &&
        widget.activeTabIndex < widget.tabs.length) {
      widget.onContentChanged(
          widget.tabs[widget.activeTabIndex], newText);
    }
  }

  void _handleEnterKey() {
    final text = _plainTextController.text;
    final selection = _plainTextController.selection;
    int lineStart = text.lastIndexOf('\n', selection.start - 1) + 1;
    if (lineStart < 0) lineStart = 0;
    final currentLine = text.substring(lineStart, selection.start);
    final match = RegExp(r'^\s*').firstMatch(currentLine);
    final indentation = match?.group(0) ?? '';
    final insertString = '\n$indentation';
    final newText =
        text.replaceRange(selection.start, selection.end, insertString);
    final newSelection = TextSelection.collapsed(
        offset: selection.start + insertString.length);
    _plainTextController.value =
        TextEditingValue(text: newText, selection: newSelection);
    if (widget.tabs.isNotEmpty &&
        widget.activeTabIndex < widget.tabs.length) {
      widget.onContentChanged(
          widget.tabs[widget.activeTabIndex], newText);
    }
  }
}
