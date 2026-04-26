import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/speech_controller.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:archive/archive.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import '../services/docx_service.dart';
import 'dart:convert';
import '../theme/app_theme.dart';
import 'dart:io';
import '../models/edit_format.dart';
import '../models/note_metadata.dart';
import '../controllers/text_style_controller.dart';
import 'package:flutter/gestures.dart';
import '../models/highlight_note.dart';
import 'duration_picker_dialog.dart';
import 'package:google_fonts/google_fonts.dart';

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
  final Function(int, int)? onPositionChanged;
  final Function(List<String>)? onSectionsChanged;
  final Function(String, String)? onRename;
  final TextStyleController textStyleController;
  final SpeechController? speechController;
  final VoidCallback? onShowSpeechSummary;
  final Function(String noteId)? onShowNote;

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
    required this.textStyleController,
    this.onPositionChanged,
    this.onSectionsChanged,
    this.onRename,
    this.speechController,
    this.onShowSpeechSummary,
    this.onShowNote,
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
  bool _isApplyingStyle = false;
  Timer? _debounceTimer;

  // PDF Viewer (pdfrx)
  final PdfViewerController _pdfController = PdfViewerController();
  List<PdfTextRanges>? _pdfSelection;
  PdfDocument? _currentPdfDocument;

  StreamSubscription? _deleteSubscription;

  @override
  void initState() {
    super.initState();
    _deleteSubscription = widget.speechController?.onDeleteSection.listen((index) {
      _deleteDividerAtIndex(index);
    });
    _plainTextController = TextEditingController();
    _plainTextController.addListener(() {
      if (widget.tabs.isNotEmpty &&
          widget.activeTabIndex < widget.tabs.length) {
        final path = widget.tabs[widget.activeTabIndex];
        widget.onContentChanged(path, _plainTextController.text);

        // Update Line and Column
        if (widget.onPositionChanged != null) {
          final selection = _plainTextController.selection;
          if (selection.isValid) {
            final textBefore = _plainTextController.text.substring(
              0,
              selection.baseOffset,
            );
            final lines = textBefore.split('\n');
            widget.onPositionChanged!(lines.length, lines.last.length + 1);
          }
        }

        // Section detection for Plain Text
        if (widget.onSectionsChanged != null) {
          final sections = _plainTextController.text.split(
            RegExp(r'\n-+\n|^-+$', multiLine: true),
          );
          widget.onSectionsChanged!(
            sections.map((s) {
              final lines = s.trim().split('\n');
              return lines.isNotEmpty ? lines.first : 'Seção';
            }).toList(),
          );
        }
      }
    });
    _plainTextFocusNode = FocusNode();
    _titleController = TextEditingController();
    _descController = TextEditingController();
    _loadCurrentTab();
    _setupStyleController();
    widget.textStyleController.addListener(_onStyleChanged);
  }

  void _setupStyleController() {
    debugPrint('DocumentView: Setting up Style Controller callbacks');
    final ctrl = widget.textStyleController;

    ctrl.onToggleBold = () {
      if (_editorState != null) {
        final selection = _editorState!.selection;
        if (selection != null) {
          _isApplyingStyle = true;
          _debounceTimer?.cancel();
          _debounceTimer = Timer(const Duration(milliseconds: 1000), () {
            _isApplyingStyle = false;
          });
          _editorState!.toggleAttribute('bold', selection: selection);
        }
      } else {
        setState(() {});
      }
    };

    ctrl.onToggleItalic = () {
      if (_editorState != null) {
        final selection = _editorState!.selection;
        if (selection != null) {
          _isApplyingStyle = true;
          _debounceTimer?.cancel();
          _debounceTimer = Timer(const Duration(milliseconds: 1000), () {
            _isApplyingStyle = false;
          });
          _editorState!.toggleAttribute('italic', selection: selection);
        }
      } else {
        setState(() {});
      }
    };

    ctrl.onApplyFontSize = (size) {
      if (_editorState != null) {
        final selection = _editorState!.selection;
        if (selection != null) {
          _isApplyingStyle = true;
          _debounceTimer?.cancel();
          // Aumentamos para 1 segundo para garantir que o editor processe a transação
          _debounceTimer = Timer(const Duration(milliseconds: 1000), () {
            _isApplyingStyle = false;
          });

          _editorState!.formatDelta(selection, {'font_size': size.toDouble()});
        }
      } else {
        setState(() {});
      }
    };

    ctrl.onInsertDivider = () {
      if (_editorState != null) {
        final selection = _editorState!.selection;
        if (selection != null) {
          final transaction = _editorState!.transaction;
          final path = selection.end.path;
          final nextPath = path.next;

          // Inserimos o divisor e o parágrafo em sequência
          transaction.insertNodes(nextPath, [
            Node(type: 'divider', attributes: {}),
            Node(type: 'paragraph', attributes: {'delta': []}),
          ]);

          // Move o cursor para o início do novo parágrafo (que agora está em nextPath + 1)
          final newParagraphPath = nextPath.next;
          transaction.afterSelection = Selection.collapsed(
            Position(path: newParagraphPath, offset: 0),
          );

          _editorState!.apply(transaction);
        }
      } else {
        // Implementação para Texto Simples (Plain Text)
        final text = _plainTextController.text;
        final selection = _plainTextController.selection;
        const divider =
            '\n--------------------------------------------------\n';

        if (selection.isValid) {
          final newText = text.replaceRange(
            selection.start,
            selection.end,
            divider,
          );
          _plainTextController.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(
              offset: selection.start + divider.length,
            ),
          );
        } else {
          _plainTextController.text += divider;
        }
      }
    };
    ctrl.onToggleNote = _onToggleNote;
  }

  void _deleteDividerAtIndex(int index) {
    if (_editorState == null) return;
    final root = _editorState!.document.root;
    final dividers = root.children.where((n) => n.type == 'divider').toList();
    if (index >= 0 && index < dividers.length) {
      final node = dividers[index];
      final transaction = _editorState!.transaction;
      transaction.deleteNode(node);
      _editorState!.apply(transaction);
    }
  }

  void _onStyleChanged() {
    if (mounted) setState(() {});
  }

  void _onToggleNote() {
    if (_editorState != null) {
      final selection = _editorState!.selection;
      if (selection != null && !selection.isCollapsed) {
        final attributes = _editorState!.getDeltaAttributesInSelectionStart();

        if (attributes != null && attributes.containsKey('note')) {
          _editorState!.formatDelta(selection, {'note': null});
        } else {
          final highlightId = 'text_h_${DateTime.now().millisecondsSinceEpoch}';
          final path = widget.tabs[widget.activeTabIndex];

          // Captura o texto do bloco atual (fallback seguro para compilação)
          final selectedText =
              _editorState!.document
                  .nodeAtPath(selection.start.path)
                  ?.delta
                  ?.toPlainText() ??
              "Destaque";

          final metadata = _getEffectiveMetadata(path);

          final newHighlight = HighlightNote(
            id: highlightId,
            content: '',
            highlightedText: selectedText,
            colorValue: 0x80FFFF00, // Amarelo semi-transparente
            type: HighlightType.text,
            startIndex: selection.startIndex,
            endIndex: selection.endIndex,
            createdAt: DateTime.now(),
          );

          final updatedHighlights = List<HighlightNote>.from(
            metadata.highlights,
          )..add(newHighlight);
          final updatedMetadata = metadata.copyWith(
            highlights: updatedHighlights,
          );

          widget.onMetadataChanged(path, updatedMetadata);
          _editorState!.formatDelta(selection, {'note': highlightId});

          // Abre o painel lateral
          widget.onShowNote?.call(highlightId);
        }
      }
    }
  }

  void _onSelectionChanged() {
    if (_isApplyingStyle) {
      return;
    }

    final selection = _editorState?.selection;
    if (selection == null) return;

    final attributes = _editorState!.getDeltaAttributesInSelectionStart();
    if (attributes != null && attributes.containsKey('note')) {
      final fullNoteId = attributes['note'] as String;
      widget.onShowNote?.call(fullNoteId);
    }
  }

  bool _isMarkdown(String path) {
    final isMd =
        path.toLowerCase().endsWith('.md') ||
        path.toLowerCase().endsWith('.docx') ||
        widget.currentFormat == EditFormat.markdown ||
        widget.currentFormat == EditFormat.docx;
    debugPrint(
      'DocumentView: _isMarkdown for $path = $isMd (format: ${widget.currentFormat})',
    );
    return isMd;
  }

  String _getContentForCurrentTab() {
    if (widget.tabs.isEmpty) return '';
    final path = widget.tabs[widget.activeTabIndex];

    if (widget.fileContents.containsKey(path)) {
      return widget.fileContents[path]!;
    }

    try {
      if (path.toLowerCase().endsWith('.jwpub') ||
          path.toLowerCase().endsWith('.pdf')) {
        return '';
      }
      final file = File(path);
      if (file.existsSync()) {
        if (path.toLowerCase().endsWith('.docx')) {
          // Para DOCX, retornamos o texto extraído
          final bytes = file.readAsBytesSync();
          return DocxService.extractText(bytes);
        }
        return file.readAsStringSync();
      }
      return '';
    } catch (e) {
      return '';
    }
  }

  void _loadCurrentTab() {
    final path = widget.tabs.isNotEmpty
        ? widget.tabs[widget.activeTabIndex]
        : '';
    final content = _getContentForCurrentTab();
    debugPrint(
      'DocumentView: Loading tab. isMarkdown=${_isMarkdown(path)}, content length=${content.length}',
    );
    if (_isMarkdown(path)) {
      _loadMarkdownEditor(content);
    } else {
      setState(() {
        _plainTextController.text = content;
        _editorState = null;
      });
    }
  }

  void _loadMarkdownEditor(String markdownContent) {
    final path = widget.tabs.isNotEmpty
        ? widget.tabs[widget.activeTabIndex]
        : '';

    debugPrint('DocumentView: Loading Markdown editor for path: $path');

    if (_lastLoadedMarkdownPath == path && _editorState != null) {
      debugPrint(
        'DocumentView: Editor already loaded for this path, skipping',
      );
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
        _editorState?.selectionNotifier.removeListener(_onSelectionChanged);
        _editorState = EditorState(document: document);
        _editorState!.selectionNotifier.addListener(_onSelectionChanged);
        debugPrint('DocumentView: EditorState initialized.');
      });

      // Listen to transaction stream for changes
      _editorSubscription = _editorState!.transactionStream.listen((value) {
        final (time, transaction, options) = value;
        if (time == TransactionTime.after) {
          if (!mounted) {
            return;
          }
          if (widget.tabs.isEmpty) {
            return;
          }
          final currentPath = widget.tabs[widget.activeTabIndex];
          final markdown = documentToMarkdown(_editorState!.document);
          widget.onContentChanged(currentPath, markdown);
          _updateSectionsMarkdown();
        }
      });

      // Selection listener for Line/Col and Style Detection
      _editorState!.selectionNotifier.addListener(() {
        final selection = _editorState!.selection;
        if (selection == null) {
          return;
        }

        // 1. Update Position (Line/Col)
        if (widget.onPositionChanged != null) {
          int lineCount = 1;
          int colCount = 1;

          final currentPath = selection.start.path;
          if (currentPath.isNotEmpty) {
            final root = _editorState!.document.root;
            final targetNodeIndex = currentPath.first;

            for (int i = 0; i < targetNodeIndex && i < root.children.length; i++) {
              final node = root.children[i];
              final text = node.delta?.toPlainText() ?? '';
              lineCount += text.isEmpty ? 1 : text.split('\n').length;
            }

            if (targetNodeIndex < root.children.length) {
              final currentNode = root.children[targetNodeIndex];
              final currentText = currentNode.delta?.toPlainText() ?? '';
              final offset = selection.start.offset;

              final textBeforeCursor = currentText.substring(0, offset.clamp(0, currentText.length));
              final linesInCurrentBlock = textBeforeCursor.split('\n');
              
              lineCount += linesInCurrentBlock.length - 1;
              colCount = linesInCurrentBlock.last.length + 1;
            }
          }
          widget.onPositionChanged!(lineCount, colCount);
        }

        // 2. Detect Styles in Selection (Detectando Atributos Inline)
        if (_isApplyingStyle) {
          return; // Ignora se estivermos aplicando um estilo manualmente
        }

        final styles = _editorState!.getDeltaAttributesInSelectionStart() ?? {};

        // Font Size detection (Chave oficial: font_size)
        final fontSizeVal = styles['font_size'] ?? styles['fontSize'];
        double fontSize = 16.0; // Sincronizado com o padrão do editor

        if (fontSizeVal is num) {
          fontSize = fontSizeVal.toDouble();
        } else if (fontSizeVal is String) {
          fontSize = double.tryParse(fontSizeVal) ?? 14.0;
        } else {
          // Se não houver font_size inline, checamos se é um Heading para mostrar o tamanho estimado
          final selection = _editorState!.selection;
          if (selection != null) {
            final path = selection.start.path;
            if (path.isNotEmpty) {
              final node = _editorState!.document.nodeAtPath(path);
              if (node != null && node.type == 'heading') {
                final level = node.attributes['level'];
                if (level == 1) {
                  fontSize = 28.0;
                } else if (level == 2) {
                  fontSize = 22.0;
                } else if (level == 3) {
                  fontSize = 18.0;
                }
              }
            }
          }
        }

        final isBold = styles['bold'] == true;
        final isItalic = styles['italic'] == true;

        // Sincroniza a barra superior
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            widget.textStyleController.updateFromSelection(
              fontSize,
              isBold,
              isItalic,
            );
          }
        });
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

    if (oldWidget.textStyleController != widget.textStyleController) {
      oldWidget.textStyleController.removeListener(_onStyleChanged);
      _setupStyleController();
      widget.textStyleController.addListener(_onStyleChanged);
    }

    final oldPath =
        oldWidget.tabs.isNotEmpty &&
            oldWidget.activeTabIndex < oldWidget.tabs.length
        ? oldWidget.tabs[oldWidget.activeTabIndex]
        : null;
    final newPath =
        widget.tabs.isNotEmpty && widget.activeTabIndex < widget.tabs.length
        ? widget.tabs[widget.activeTabIndex]
        : null;

    final tabChanged =
        oldPath != newPath ||
        oldWidget.tabs.length != widget.tabs.length ||
        oldWidget.currentFormat != widget.currentFormat;

    debugPrint(
      'DocumentView: didUpdateWidget. tabChanged=$tabChanged (oldPath=$oldPath, newPath=$newPath, oldFormat=${oldWidget.currentFormat}, newFormat=${widget.currentFormat})',
    );

    if (tabChanged) {
      _editorSubscription?.cancel();
      _editorSubscription = null;
      _editorState = null;
      _lastLoadedMarkdownPath = null;
      _loadCurrentTab();
      // Update header controllers for new tab
      final newPath =
          widget.tabs.isNotEmpty && widget.activeTabIndex < widget.tabs.length
          ? widget.tabs[widget.activeTabIndex]
          : null;
      if (newPath != null) {
        final meta = _getEffectiveMetadata(newPath);
        _titleController.text = meta.title;
        _descController.text = meta.description;
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    _deleteSubscription?.cancel();
    _plainTextController.dispose();
    _plainTextFocusNode.dispose();
    _titleController.dispose();
    _descController.dispose();
    _editorSubscription?.cancel();
    widget.textStyleController.removeListener(_onStyleChanged);
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

  Widget _buildPdfView(String path) {
    // Se o formato selecionado for PDF mas o arquivo for .txt ou .md,
    // mostramos uma tela de exportação em vez de tentar abrir o PDF (que causaria erro/tela azul)
    if (!path.toLowerCase().endsWith('.pdf')) {
      return _buildPdfPlaceholder(path);
    }

    debugPrint('DocumentView: Building PDF view (pdfrx) for path: $path');
    if (!File(path).existsSync()) {
      debugPrint('DocumentView: PDF file does NOT exist at path: $path');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              'Arquivo PDF não encontrado:\n$path',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        PdfViewer.file(
          path,
          controller: _pdfController,
          params: PdfViewerParams(
            enableTextSelection: true,
            onDocumentChanged: (document) {
              if (document != null) {
                debugPrint(
                  'DocumentView: PDF loaded successfully: ${document.pages.length} pages',
                );
                _currentPdfDocument = document;
              }
            },
            onTextSelectionChange: (selection) {
              debugPrint(
                'DocumentView: PDF Selection changed: ${selection.length} ranges',
              );
              setState(() {
                _pdfSelection = selection;
              });
            },
            // Render highlights
            pageOverlaysBuilder: (context, pageRect, page) {
              return [_buildPdfHighlightsOverlay(page, pageRect)];
            },
          ),
        ),
        if (_pdfSelection != null && _pdfSelection!.isNotEmpty)
          _buildPdfSelectionToolbar(),
      ],
    );
  }

  Widget _buildPdfPlaceholder(String path) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: AppTheme.background,
      child: Column(
        children: [
          // Elegant Header for the placeholder
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            color: AppTheme.surface,
            child: Row(
              children: [
                const Icon(
                  Icons.picture_as_pdf,
                  color: AppTheme.accent,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  'Visualização de PDF',
                  style: AppTheme.uiStyle.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppTheme.warning.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: AppTheme.warning,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Modo Exportação',
                        style: TextStyle(
                          color: AppTheme.warning,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Dynamic Icon Container
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.easeOutBack,
                        builder: (context, value, child) {
                          return Transform.scale(
                            scale: value,
                            child: Opacity(opacity: value, child: child),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(40),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppTheme.accent.withValues(alpha: 0.2),
                                AppTheme.accent.withValues(alpha: 0.05),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.accent.withValues(alpha: 0.1),
                                blurRadius: 40,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.auto_awesome,
                            color: AppTheme.accent,
                            size: 100,
                          ),
                        ),
                      ),
                      const SizedBox(height: 48),
                      Text(
                        'Gerar Documento PDF',
                        style: GoogleFonts.outfit(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                          letterSpacing: -0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'O arquivo atual é um documento de texto.\nPara visualizar o resultado final com a formatação profissional, clique no botão abaixo para gerar o arquivo PDF.',
                        style: TextStyle(
                          fontSize: 18,
                          color: AppTheme.textSecondary,
                          height: 1.6,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 56),
                      // Premium Action Button
                      InkWell(
                        onTap: () => widget.onSaveFile(),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 20,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.accent,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.accent.withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.picture_as_pdf,
                                color: Colors.white,
                                size: 24,
                              ),
                              const SizedBox(width: 16),
                              Text(
                                'EXPORTAR PARA PDF',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPdfHighlightsOverlay(PdfPage page, Rect pageRect) {
    final path = widget.tabs.isNotEmpty
        ? widget.tabs[widget.activeTabIndex]
        : null;
    if (path == null) return const SizedBox.shrink();

    final metadata = widget.noteMetadataMap[path];
    if (metadata == null) return const SizedBox.shrink();

    final highlights = metadata.highlights
        .where((h) => h.type == HighlightType.pdf)
        .toList();
    final pageNumber = page.pageNumber;

    if (highlights.isNotEmpty) {
      debugPrint(
        'DocumentView: Building highlights overlay for page $pageNumber. Total PDF highlights: ${highlights.length}',
      );
    }

    // Scaling factors
    final double scaleX = pageRect.width / page.width;
    final double scaleY = pageRect.height / page.height;

    return Stack(
      children: highlights.expand((h) {
        if (h.pdfRegions == null) return <Widget>[];

        return h.pdfRegions!.where((r) => r.pageNumber == pageNumber).map<
          Widget
        >((region) {
          // Scale the PDF coordinates to the rendered page size
          // Fix Y-axis inversion: Flutter top = (pageHeight - pdfTop)
          final scaledRect = Rect.fromLTWH(
            region.bounds.left * scaleX,
            (page.height - region.bounds.top) * scaleY,
            region.bounds.width * scaleX,
            region.bounds.height * scaleY,
          );

          debugPrint(
            'DocumentView: Rendering highlight ${h.id} on page $pageNumber at $scaledRect',
          );

          return Positioned.fromRect(
            rect: scaledRect,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                debugPrint('DocumentView: Tapped highlight ${h.id}');
                widget.onShowNote?.call(h.id);
              },
              child: Container(
                color: Color(h.colorValue).withValues(alpha: 0.4),
              ),
            ),
          );
        });
      }).toList(),
    );
  }

  Widget _buildPdfSelectionToolbar() {
    return Positioned(
      top: 50,
      right: 20,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        color: AppTheme.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.edit_note_rounded, color: AppTheme.accent),
                onPressed: _onAddPdfNote,
                tooltip: 'Marcar e Adicionar Nota',
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  setState(() {
                    _pdfSelection = null;
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onAddPdfNote() {
    debugPrint(
      'DocumentView: _onAddPdfNote called. Selection present? ${_pdfSelection != null}. Empty? ${_pdfSelection?.isEmpty}',
    );
    if (_pdfSelection == null ||
        _pdfSelection!.isEmpty ||
        _currentPdfDocument == null) {
      debugPrint(
        'DocumentView: _onAddPdfNote aborted: selection or document missing',
      );
      return;
    }

    final selection = _pdfSelection!;
    // Join text from multiple ranges if necessary
    final String selectedText = selection.map((r) => r.text).join(' ');

    List<PdfRegion> regions = [];
    for (var ranges in selection) {
      // Use the actual page number from the selection ranges
      final int pNum = ranges.pageNumber;
      for (var range in ranges.ranges) {
        final dynamic r = range;

        // Use fragments if available for more precise highlighting
        bool addedFromFragments = false;
        try {
          if (r.fragments != null && r.fragments.isNotEmpty) {
            for (var fragment in r.fragments) {
              final dynamic f = fragment;
              regions.add(
                PdfRegion(
                  pageNumber: pNum,
                  bounds: Rect.fromLTWH(
                    f.bounds.left,
                    f.bounds.top,
                    f.bounds.width,
                    f.bounds.height,
                  ),
                ),
              );
            }
            addedFromFragments = true;
          }
        } catch (_) {}

        if (!addedFromFragments) {
          Rect? bounds;
          try {
            if (r.bounds != null) {
              bounds = Rect.fromLTWH(
                r.bounds.left,
                r.bounds.top,
                r.bounds.width,
                r.bounds.height,
              );
            }
          } catch (_) {}

          if (bounds != null) {
            regions.add(PdfRegion(pageNumber: pNum, bounds: bounds));
          }
        }
      }
    }

    debugPrint(
      'DocumentView: Extracted ${regions.length} regions for selected text: "$selectedText"',
    );

    if (regions.isEmpty) {
      debugPrint('DocumentView: _onAddPdfNote aborted: no regions found');
      return;
    }

    final path = widget.tabs[widget.activeTabIndex];
    final metadata = widget.noteMetadataMap[path] ?? NoteMetadata();

    final newHighlight = HighlightNote(
      id: 'pdf_h_${DateTime.now().millisecondsSinceEpoch}',
      content: '',
      highlightedText: selectedText,
      colorValue: 0x80FFFF00, // Default semi-transparent yellow
      type: HighlightType.pdf,
      pdfRegions: regions,
    );

    final updatedHighlights = List<HighlightNote>.from(metadata.highlights)
      ..add(newHighlight);
    final updatedMetadata = metadata.copyWith(highlights: updatedHighlights);

    debugPrint(
      'DocumentView: Saving metadata with ${updatedHighlights.length} highlights',
    );
    widget.onMetadataChanged(path, updatedMetadata);

    setState(() {
      _pdfSelection = null;
    });

    widget.onShowNote?.call(newHighlight.id);
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
            child: Text(
              'Error loading publication: ${snapshot.error}',
              style: TextStyle(color: Colors.red.shade300),
            ),
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
              child: Row(
                children: [
                  Icon(Icons.library_books, color: AppTheme.accent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Text(
                    pub['symbol'] ?? '',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
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
                        color: AppTheme.textSecondary.withValues(alpha: 0.1),
                      ),
                    ),
                    margin: const EdgeInsets.only(bottom: 16),
                    child: ExpansionTile(
                      initiallyExpanded: index == 0,
                      title: Text(
                        doc['Title'] ?? 'No Title',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            doc['Content'] ?? '',
                            style: AppTheme.codeTextStyle.copyWith(
                              fontSize: 13,
                            ),
                          ),
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
    if (manifestFile == null) throw Exception('manifest.json não encontrado');
    final manifest = json.decode(
      utf8.decode(manifestFile.content as List<int>),
    );

    // Implementação JWPUB (Pausada em 25/04/2026)
    // Status: Já conseguimos descobrir o banco de dados correto (ex: CA-brtk26_T_007.db)
    // e identificar as tabelas de conteúdo (Document, DocumentParagraph, Extract).
    // O próximo passo seria refinar a ordenação dos blocos de texto e a formatação Markdown.

    // Discover the database file
    // Discover all potential database files
    List<ArchiveFile> potentialDbs = [];

    // Look in root
    for (var f in archive.files) {
      if (f.name.toLowerCase().endsWith('.db') ||
          f.name.toLowerCase() == 'contents') {
        potentialDbs.add(f);
      }
    }

    // Look in nested 'contents' zip if it exists
    final contentsFile = archive.findFile('contents');
    if (contentsFile != null) {
      // Try to treat it as a database first
      potentialDbs.add(contentsFile);

      // Also try to treat it as a ZIP
      try {
        final bytes = contentsFile.content as List<int>;
        final contentsArchive = ZipDecoder().decodeBytes(bytes);
        for (var f in contentsArchive.files) {
          if (f.name.toLowerCase().endsWith('.db')) {
            potentialDbs.add(f);
          }
        }
      } catch (_) {}
    }

    if (potentialDbs.isEmpty) {
      throw Exception('Banco de dados (.db) não encontrado no arquivo JWPUB');
    }

    // Pick the best database
    ArchiveFile? dbFile;
    int maxTables = -1;
    final tempDir = await getTemporaryDirectory();
    final String foundFiles = potentialDbs.map((f) => f.name).join(', ');
    debugPrint('Potential databases found: $foundFiles');

    for (var potential in potentialDbs) {
      final pPath = p.join(
        tempDir.path,
        'check_db_${DateTime.now().millisecondsSinceEpoch}_${potentialDbs.indexOf(potential)}.db',
      );

      try {
        final bytes = potential.content as List<int>;
        await File(pPath).writeAsBytes(bytes);

        final checkDb = await openDatabase(pPath, readOnly: true);
        final tablesResult = await checkDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        );
        final List<String> currentTableNames = tablesResult
            .map((t) => t['name'] as String)
            .toList();
        await checkDb.close();

        debugPrint(
          'DB ${potential.name} has ${currentTableNames.length} tables: ${currentTableNames.join(", ")}',
        );

        if (currentTableNames.contains('Document')) {
          dbFile = potential;
          break; // Found the primary content database!
        }

        if (currentTableNames.length > maxTables) {
          maxTables = currentTableNames.length;
          dbFile = potential;
        }
      } catch (e) {
        debugPrint(
          'File ${potential.name} is not a valid SQLite database or bytes extraction failed: $e',
        );
      }
    }

    if (dbFile == null) {
      throw Exception(
        'Não foi possível encontrar um banco de dados válido no arquivo JWPUB',
      );
    }

    final dbPath = p.join(
      tempDir.path,
      'jwpub_main_${DateTime.now().millisecondsSinceEpoch}.db',
    );
    final dbBytes = dbFile.content as List<int>;
    await File(dbPath).writeAsBytes(dbBytes);

    final Database db = await openDatabase(dbPath, readOnly: true);
    List<Map<String, dynamic>> documents = [];
    List<String> tableNames = [];

    try {
      // 1. Get all tables in the database
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      );
      tableNames = tables.map((t) => t['name'] as String).toList();

      // 2. Strategy A: Standard JWPUB Document Structure
      if (tableNames.contains('Document')) {
        final columns = await db.rawQuery('PRAGMA table_info(Document)');
        final availableColumns = columns
            .map((c) => c['name'].toString())
            .toList();

        final idCol = availableColumns.firstWhere((c) {
          final l = c.toLowerCase();
          return l == 'documentid' || l == 'id' || l == 'docid';
        }, orElse: () => '');
        final titleCol = availableColumns.firstWhere((c) {
          final l = c.toLowerCase();
          return l == 'title' || l == 'displaytitle' || l == 'label';
        }, orElse: () => '');
        final contentCol = availableColumns.firstWhere((c) {
          final l = c.toLowerCase();
          return l.contains('content') ||
              l.contains('text') ||
              l.contains('markup') ||
              l.contains('body') ||
              l.contains('markdown');
        }, orElse: () => '');

        if (idCol.isNotEmpty || contentCol.isNotEmpty) {
          final List<String> queryCols = [];
          if (idCol.isNotEmpty) queryCols.add(idCol);
          if (titleCol.isNotEmpty) queryCols.add(titleCol);
          if (contentCol.isNotEmpty) queryCols.add(contentCol);

          final docMaps = await db.query('Document', columns: queryCols);

          for (var docMap in docMaps) {
            final docId = idCol.isNotEmpty ? docMap[idCol] : 0;
            final title = titleCol.isNotEmpty
                ? (docMap[titleCol]?.toString() ?? 'Untitled')
                : 'Document $docId';
            // Acumular conteúdo de múltiplas fontes
            final List<String> contentParts = [];

            // 1. Tenta conteúdo direto da tabela Document
            if (contentCol.isNotEmpty) {
              final val = docMap[contentCol];
              String direct = '';
              if (val is String) {
                direct = val;
              } else if (val is List<int>) {
                direct = _decodeBlob(val);
              }
              if (direct.trim().length > 2) {
                contentParts.add(direct);
              }
            }

            // 2. Tenta tabelas relacionadas (DocumentParagraph, etc.)
            if (idCol.isNotEmpty) {
              for (var relatedTable in [
                'DocumentParagraph',
                'TextUnit',
                'Block',
                'Paragraph',
                'Verse',
                'BibleVerse',
                'IndependentBlock',
              ]) {
                if (tableNames.contains(relatedTable)) {
                  try {
                    final relCols = await db.rawQuery(
                      'PRAGMA table_info($relatedTable)',
                    );
                    final relColNames = relCols
                        .map((c) => c['name'].toString())
                        .toList();

                    final relIdCol = relColNames.firstWhere((c) {
                      final l = c.toLowerCase();
                      return l == 'documentid' ||
                          l == 'id' ||
                          l == 'docid' ||
                          l == 'blockid';
                    }, orElse: () => '');

                    final relContentCol = relColNames.firstWhere((c) {
                      final l = c.toLowerCase();
                      return l.contains('content') ||
                          l.contains('text') ||
                          l.contains('markup') ||
                          l.contains('body') ||
                          l.contains('verse');
                    }, orElse: () => '');

                    if (relIdCol.isNotEmpty && relContentCol.isNotEmpty) {
                      final relMaps = await db.query(
                        relatedTable,
                        columns: [relContentCol],
                        where: '$relIdCol = ?',
                        whereArgs: [docId],
                        orderBy: relColNames.contains('Sequence')
                            ? 'Sequence'
                            : null,
                      );
                      if (relMaps.isNotEmpty) {
                        final relText = relMaps
                            .map((m) {
                              final v = m[relContentCol];
                              if (v is List<int>) return _decodeBlob(v);
                              return v?.toString() ?? '';
                            })
                            .join('\n\n');
                        if (relText.trim().length > 5 &&
                            !RegExp(r'^\d+$').hasMatch(relText.trim())) {
                          contentParts.add(relText);
                        }
                      }
                    }
                  } catch (_) {}
                }
              }
            }

            String contentText = contentParts.join('\n\n');
            contentText = contentText.replaceAll(RegExp(r'<[^>]*>'), '');
            contentText = contentText
                .replaceAll(RegExp(r'\n{3,}'), '\n\n')
                .trim();

            if (contentText.isNotEmpty) {
              documents.add({'Title': title, 'Content': contentText});
            }
          }
        }
      }

      // 3. Strategy B: Generic Content Search (Fallback for Bibles, Yearbooks, etc.)
      if (documents.isEmpty) {
        for (var table in tableNames) {
          if ([
            'Document',
            'sqlite_sequence',
            'android_metadata',
          ].contains(table)) {
            continue;
          }

          try {
            final columns = await db.rawQuery('PRAGMA table_info($table)');
            final colNames = columns.map((c) => c['name'].toString()).toList();

            final contentCol = colNames.firstWhere((c) {
              final lower = c.toLowerCase();
              return lower.contains('content') ||
                  lower.contains('text') ||
                  lower.contains('markup') ||
                  lower.contains('markdown') ||
                  lower.contains('body') ||
                  lower.contains('verse');
            }, orElse: () => '');
            if (contentCol.isNotEmpty) {
              final maps = await db.query(
                table,
                columns: [contentCol],
                limit: 500,
              ); // Limit to avoid massive dump
              if (maps.isNotEmpty) {
                String fullText = maps
                    .map((m) {
                      final val = m[contentCol];
                      if (val is List<int>) return _decodeBlob(val);
                      return val?.toString() ?? '';
                    })
                    .join('\n\n');
                fullText = fullText.replaceAll(RegExp(r'<[^>]*>'), '').trim();

                // Filtro para ignorar tabelas que só contém números ou metadados curtos
                if (fullText.length > 20 &&
                    !RegExp(r'^\d+$').hasMatch(fullText)) {
                  documents.add({
                    'Title': 'Conteúdo de $table',
                    'Content': fullText,
                  });
                }
              }
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Error decoding JWPUB database: $e');
    }

    final String foundTables = tableNames.join(', ');
    await db.close();

    if (documents.isEmpty) {
      throw Exception(
        'Não foi possível encontrar texto legível no arquivo. Tabelas encontradas: $foundTables',
      );
    }
    return {'manifest': manifest, 'documents': documents};
  }

  NoteMetadata _getEffectiveMetadata(String path) {
    final meta = widget.noteMetadataMap[path] ?? NoteMetadata();
    if (meta.title.isEmpty) {
      String name = p.basenameWithoutExtension(path);
      // Optional: capitalize first letter or handle 'Untitled'
      return meta.copyWith(title: name);
    }
    return meta;
  }

  String _decodeBlob(List<int> blob) {
    if (blob.isEmpty) return '';

    // 1. Tentar ZLib (Padrão mais comum nas publicações da JW)
    try {
      final decoded = ZLibDecoder().decodeBytes(blob);
      return utf8.decode(decoded, allowMalformed: true);
    } catch (_) {}

    // 2. Tentar GZip
    try {
      final decoded = GZipDecoder().decodeBytes(blob);
      return utf8.decode(decoded, allowMalformed: true);
    } catch (_) {}

    // 3. Tentar Inflate direto
    try {
      final decoded = Inflate(blob).getBytes();
      return utf8.decode(decoded, allowMalformed: true);
    } catch (_) {}

    // 4. Tentar UTF-8 puro (muitas vezes o texto está direto no BLOB)
    try {
      return utf8.decode(blob, allowMalformed: true);
    } catch (_) {}

    // 5. Brute Force: Extrair apenas caracteres imprimíveis
    // Útil para extrair fragmentos de texto de estruturas binárias (como Protobuf)
    try {
      final printable = blob
          .where(
            (b) => (b >= 32 && b <= 126) || b == 10 || b == 13 || (b >= 160),
          )
          .toList();
      if (printable.length > blob.length * 0.3) {
        // Se pelo menos 30% parecer texto
        return utf8.decode(printable, allowMalformed: true);
      }
    } catch (_) {}

    return '[Conteúdo Binário: ${blob.length} bytes]';
  }

  // ─── MARKDOWN EDITOR ─────────────────────────────────────────────────────

  Widget _buildMarkdownEditor() {
    if (_editorState == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Modern style for AppFlowy v6.2.0
    final editorStyle = EditorStyle.desktop(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      cursorColor: AppTheme.accent,
      selectionColor: AppTheme.accent.withValues(alpha: 0.3),
      textStyleConfiguration: TextStyleConfiguration(
        text: AppTheme.codeTextStyle.copyWith(
          fontSize: widget.textStyleController.fontSize,
          height: 1.5,
          color: AppTheme.textPrimary,
          fontWeight: FontWeight.normal,
          fontStyle: FontStyle.normal,
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
      textSpanDecorator: (context, node, index, insert, original, current) {
        final attributes = insert.attributes;
        TextSpan result = current;

        // Apply custom font size if present
        if (attributes != null && attributes.containsKey('font_size')) {
          final size = (attributes['font_size'] as num).toDouble();
          result = TextSpan(
            children: [result],
            style: TextStyle(fontSize: size),
          );
        }

        if (attributes != null && attributes.containsKey('note')) {
          final highlightId = attributes['note'] as String;
          final path =
              widget.tabs.isNotEmpty ? widget.tabs[widget.activeTabIndex] : '';
          final metadata = widget.noteMetadataMap[path];

          if (metadata != null) {
            final highlight =
                metadata.highlights.where((h) => h.id == highlightId).firstOrNull;
            if (highlight != null) {
              final color = Color(highlight.colorValue);
              return TextSpan(
                children: [result],
                style: TextStyle(backgroundColor: color.withValues(alpha: 0.5)),
                recognizer: TapGestureRecognizer()
                  ..onTap = () {
                    widget.onShowNote?.call(highlightId);
                  },
              );
            }
          }

          return TextSpan(
            children: [result],
            style: TextStyle(
              backgroundColor: const Color(0xFFFBC02D).withValues(alpha: 0.5),
            ),
          );
        }
        return result;
      },
    );

    final path = widget.tabs.isNotEmpty
        ? widget.tabs[widget.activeTabIndex]
        : '';
    final metadata = _getEffectiveMetadata(path);

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
        final isList =
            node.type == BulletedListBlockKeys.type ||
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

    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showEditorContextMenu(context, details.globalPosition);
      },
      child: AppFlowyEditor(
        editorState: _editorState!,
        editorStyle: editorStyle,
        autoFocus: false,
        editable: true,
        header: _buildNoteHeader(path, metadata),
        characterShortcutEvents: [
          customInsertNewLine,
          ...standardCharacterShortcutEvents.where((e) => e.character != '\n'),
        ],
        commandShortcutEvents: [
          customTabCommand,
          ...standardCommandShortcutEvents.where((e) => e.key != 'indent'),
        ],
        blockComponentBuilders: {
          ...standardBlockComponentBuilderMap,
          'divider': CustomHorizontalRuleBuilder(
            speechController: widget.speechController,
            editorState: _editorState!,
            onShowSpeechSummary: widget.onShowSpeechSummary,
          ),
          'finalize_timer': FinalizeTimerBuilder(
            speechController: widget.speechController,
            editorState: _editorState!,
          ),
        },
      ),
    );
  }

  void _showEditorContextMenu(BuildContext context, Offset position) async {
    final activeTab = widget.tabs.isNotEmpty ? widget.tabs[widget.activeTabIndex] : null;
    
    // Capture selection before focus is lost to the popup menu
    final selection = _editorState?.selection;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: AppTheme.sidebarBackground,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem(
          value: 'copy',
          child: Row(
            children: [
              Icon(Icons.copy, size: 18, color: AppTheme.textPrimary),
              const SizedBox(width: 12),
              Text('Copiar', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'cut',
          child: Row(
            children: [
              Icon(Icons.cut, size: 18, color: AppTheme.textPrimary),
              const SizedBox(width: 12),
              Text('Recortar', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'paste',
          child: Row(
            children: [
              Icon(Icons.paste, size: 18, color: AppTheme.textPrimary),
              const SizedBox(width: 12),
              Text('Colar', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'divider',
          child: Row(
            children: [
              Icon(Icons.more_horiz, size: 18, color: AppTheme.textPrimary),
              const SizedBox(width: 12),
              Text('Divisor de Tempo', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'finalize',
          child: Row(
            children: [
              Icon(Icons.stop_circle_outlined, size: 18, color: AppTheme.error),
              const SizedBox(width: 12),
              Text('Botão Finalizar Tempo', style: TextStyle(color: AppTheme.error, fontSize: 13)),
            ],
          ),
        ),
      ],
    );

    if (result == null) return;

    // Restore selection if it was lost
    if (selection != null) {
      _editorState?.updateSelectionWithReason(selection);
    }

    switch (result) {
      case 'copy':
        copyCommand.handler(_editorState!);
        break;
      case 'cut':
        cutCommand.handler(_editorState!);
        break;
      case 'paste':
        pasteCommand.handler(_editorState!);
        break;
      case 'rename':
        if (activeTab != null) {
          widget.onRename?.call(activeTab, activeTab.split('/').last);
        }
        break;
      case 'divider':
        widget.textStyleController.onInsertDivider?.call();
        break;
      case 'finalize':
        _insertFinalizeTimer();
        break;
    }
  }

  // ─── NOTE HEADER (title + description) ────────────────────────────────────

  Widget _buildNoteHeader(String path, NoteMetadata metadata) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tema / Título da nota
          TextField(
            controller: _titleController,
            onChanged: (val) {
              widget.onMetadataChanged(path, metadata.copyWith(title: val));
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
          const SizedBox(height: 8),
          Divider(
            height: 1,
            color: AppTheme.textSecondary.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // ─── PLAIN TEXT EDITOR ───────────────────────────────────────────────────

  Widget _buildPlainTextEditor() {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
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
              widget.onContentChanged(widget.tabs[widget.activeTabIndex], text);
            }
          },
          maxLines: null,
          expands: true,
          style: AppTheme.codeTextStyle.copyWith(
            fontSize: widget.textStyleController.fontSize,
            fontWeight: widget.textStyleController.isBold
                ? FontWeight.bold
                : FontWeight.normal,
            fontStyle: widget.textStyleController.isItalic
                ? FontStyle.italic
                : FontStyle.normal,
          ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
          keyboardType: TextInputType.multiline,
          textAlignVertical: TextAlignVertical.top,
          contextMenuBuilder: (context, editableTextState) {
            return AdaptiveTextSelectionToolbar.buttonItems(
              anchors: editableTextState.contextMenuAnchors,
              buttonItems: [
                ...editableTextState.contextMenuButtonItems,
                ContextMenuButtonItem(
                  label: 'Divisor de Tempo',
                  onPressed: () {
                    widget.textStyleController.onInsertDivider?.call();
                    editableTextState.hideToolbar();
                  },
                ),
                ContextMenuButtonItem(
                  label: 'Botão Finalizar',
                  onPressed: () {
                    // Para texto puro, inserimos apenas o marcador markdown
                    final text = _plainTextController.text;
                    final selection = _plainTextController.selection;
                    final newText = text.replaceRange(
                      selection.start,
                      selection.end,
                      '\n\n[finalize_timer]\n\n',
                    );
                    _plainTextController.text = newText;
                    editableTextState.hideToolbar();
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ─── MAIN BUILD ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final activeTab = widget.tabs.isNotEmpty
        ? widget.tabs[widget.activeTabIndex]
        : null;
    final format =
        widget.currentFormat ??
        (activeTab != null ? EditFormat.fromPath(activeTab) : EditFormat.txt);

    debugPrint(
      'DocumentView: build. activeTab=$activeTab, format=$format, isMarkdown=${_isMarkdown(activeTab ?? "")}',
    );

    return Container(
      color: AppTheme.background,
      child: Column(
        children: [
          _buildTabs(),
          const Divider(height: 1),
          Expanded(
            child: widget.tabs.isEmpty
                ? _buildEmptyState()
                : format == EditFormat.jwpub
                ? _buildPublicationView(widget.tabs[widget.activeTabIndex])
                : format == EditFormat.pdf
                ? _buildPdfView(widget.tabs[widget.activeTabIndex])
                : format == EditFormat.docx
                ? _buildMarkdownEditor()
                : format == EditFormat.markdown
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 64),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Welcome Text
              Text(
                'Nenhum arquivo aberto',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Abra um arquivo para começar a editar.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textSecondary.withValues(alpha: 0.6),
                  fontSize: 20,
                  fontWeight: FontWeight.w300,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 80),

              // Action List
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 450),
                child: Column(
                  children: [
                    _buildWelcomeActionCard(
                      icon: Icons.note_add_rounded,
                      title: 'Novo Arquivo',
                      description: 'Criar um novo arquivo vazio.',
                      onTap: widget.onNewTab,
                      iconColor: Colors.green,
                    ),
                    const SizedBox(height: 12),
                    _buildWelcomeActionCard(
                      icon: Icons.folder_rounded,
                      title: 'Abrir Arquivo',
                      description: 'Abrir um arquivo salvo.',
                      onTap: widget.onOpenFile,
                      iconColor: Colors.orange.shade300,
                    ),
                    const SizedBox(height: 12),
                    _buildWelcomeActionCard(
                      icon: Icons.create_new_folder_rounded,
                      title: 'Abrir Pasta',
                      description:
                          'Adicionar uma pasta de projeto à barra lateral.',
                      onTap: widget.onOpenFolder,
                      iconColor: Colors.purple.shade300,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 96),

              // Tips or Footer
              Text(
                'Dica: Use a barra superior para alternar entre Markdown, Texto Simples, PDF e DOCX',
                style: TextStyle(
                  color: AppTheme.textSecondary.withValues(alpha: 0.3),
                  fontSize: 13,
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
    Color? iconColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      hoverColor: AppTheme.textSecondary.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 280;
            return Flex(
              direction: isNarrow ? Axis.vertical : Axis.horizontal,
              crossAxisAlignment: isNarrow
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (iconColor ?? AppTheme.accent).withValues(
                      alpha: 0.1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: 36,
                    color: iconColor ?? AppTheme.accent,
                  ),
                ),
                SizedBox(width: isNarrow ? 0 : 24, height: isNarrow ? 12 : 0),
                isNarrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: TextStyle(
                              color: AppTheme.textSecondary.withValues(
                                alpha: 0.7,
                              ),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      )
                    : Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              description,
                              style: TextStyle(
                                color: AppTheme.textSecondary.withValues(
                                  alpha: 0.7,
                                ),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      height: 36,
      color: AppTheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Row(
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
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.background
                                  : Colors.transparent,
                              border: isSelected
                                  ? Border(
                                      bottom: BorderSide(
                                        color: AppTheme.accent,
                                        width: 2,
                                      ),
                                    )
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _getFileIcon(filename),
                                  size: 14,
                                  color: isSelected
                                      ? AppTheme.accent
                                      : AppTheme.textSecondary,
                                ),
                                const SizedBox(width: 8),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 200),
                                  child: Text(
                                    filename,
                                    style: TextStyle(
                                      color: isSelected
                                          ? AppTheme.textPrimary
                                          : AppTheme.textSecondary,
                                      fontSize: 13,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Tooltip(
                                  message: 'Fechar Aba',
                                  child: InkWell(
                                    onTap: () => widget.onCloseTab(index),
                                    child: Icon(
                                      Icons.close,
                                      size: 14,
                                      color: AppTheme.textSecondary,
                                    ),
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
              if (constraints.maxWidth >= 36)
                GestureDetector(
                  onTap: widget.onNewTab,
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    child: const Icon(Icons.add, size: 18),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _handleTabKey() {
    final text = _plainTextController.text;
    final selection = _plainTextController.selection;
    final tabString = widget.insertSpaces ? ' ' * widget.tabWidth : '\t';
    final newText = text.replaceRange(
      selection.start,
      selection.end,
      tabString,
    );
    final newSelection = TextSelection.collapsed(
      offset: selection.start + tabString.length,
    );
    _plainTextController.value = TextEditingValue(
      text: newText,
      selection: newSelection,
    );
    if (widget.tabs.isNotEmpty && widget.activeTabIndex < widget.tabs.length) {
      widget.onContentChanged(widget.tabs[widget.activeTabIndex], newText);
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
    final newText = text.replaceRange(
      selection.start,
      selection.end,
      insertString,
    );
    final newSelection = TextSelection.collapsed(
      offset: selection.start + insertString.length,
    );
    _plainTextController.value = TextEditingValue(
      text: newText,
      selection: newSelection,
    );
    if (widget.tabs.isNotEmpty && widget.activeTabIndex < widget.tabs.length) {
      widget.onContentChanged(widget.tabs[widget.activeTabIndex], newText);
    }
  }

  void _updateSectionsMarkdown() {
    if (_editorState == null || widget.onSectionsChanged == null) return;

    final nodes = _editorState!.document.root.children;
    List<String> sections = [];
    String currentTitle = '';

    for (var node in nodes) {
      if (node.type == 'divider') {
        sections.add(currentTitle.trim());
        currentTitle = '';
      } else if (currentTitle.isEmpty &&
          (node.type == 'heading' || node.type == 'paragraph')) {
        final delta = node.attributes['delta'];
        String text = '';
        if (delta is Delta) {
          text = delta.toPlainText().trim();
        }
        if (text.isNotEmpty) {
          currentTitle = text.length > 30
              ? '${text.substring(0, 30)}...'
              : text;
        }
      }
    }
    // Add last section
    sections.add(currentTitle.trim());

    widget.onSectionsChanged!(sections);
  }

  void _insertFinalizeTimer() {
    if (_editorState != null) {
      final selection = _editorState!.selection;
      if (selection != null) {
        final transaction = _editorState!.transaction;
        transaction.insertNodes(selection.end.path.next, [
          Node(type: 'finalize_timer', attributes: {}),
          Node(type: 'paragraph', attributes: {'delta': []}),
        ]);
        _editorState!.apply(transaction);
      }
    }
  }
}

String _formatDuration(Duration d) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  final minutes = twoDigits(d.inMinutes.remainder(60));
  final seconds = twoDigits(d.inSeconds.remainder(60));
  return "$minutes:$seconds";
}

class CustomHorizontalRuleBuilder extends BlockComponentBuilder {
  final SpeechController? speechController;
  final EditorState editorState;
  final VoidCallback? onShowSpeechSummary;

  CustomHorizontalRuleBuilder({
    this.speechController,
    required this.editorState,
    this.onShowSpeechSummary,
  });

  @override
  BlockComponentWidget build(BlockComponentContext blockContext) {
    final standardBuilder = standardBlockComponentBuilderMap['divider']!;
    final innerWidget = standardBuilder.build(blockContext);

    // Encontrar o índice deste divisor na lista de divisores do documento
    int dividerIndex = 0;
    final root = editorState.document.root;
    final dividers = root.children.where((n) => n.type == 'divider').toList();
    dividerIndex = dividers.indexOf(blockContext.node);

    return CustomHorizontalRule(
      key: blockContext.node.key,
      inner: innerWidget,
      speechController: speechController,
      sectionIndex: dividerIndex,
      onShowSpeechSummary: onShowSpeechSummary,
      editorState: editorState,
    );
  }

  @override
  BlockComponentValidate get validate =>
      (node) => node.type == 'divider';
}

class CustomHorizontalRule extends StatelessWidget
    implements BlockComponentWidget {
  final BlockComponentWidget inner;
  final SpeechController? speechController;
  final int sectionIndex;
  final VoidCallback? onShowSpeechSummary;
  final EditorState editorState;

  const CustomHorizontalRule({
    super.key,
    required this.inner,
    this.speechController,
    required this.sectionIndex,
    this.onShowSpeechSummary,
    required this.editorState,
  });

  @override
  Node get node => inner.node;

  @override
  bool get showActions => inner.showActions;

  @override
  BlockComponentActionBuilder? get actionBuilder => inner.actionBuilder;

  @override
  BlockComponentActionTrailingBuilder? get actionTrailingBuilder =>
      inner.actionTrailingBuilder;

  @override
  BlockComponentConfiguration get configuration => inner.configuration;

  @override
  Widget build(BuildContext context) {
    if (speechController == null) return inner;

    return ListenableBuilder(
      listenable: speechController!,
      builder: (context, _) {
        final isCurrent = speechController!.currentSectionIndex == sectionIndex;
        final isFinished = speechController!.currentSectionIndex > sectionIndex;

        // Tempo da seção para a barra de progresso
        double progress = 0.0;
        if (isCurrent && sectionIndex < speechController!.sections.length) {
          final section = speechController!.sections[sectionIndex];
          if (section.adjustedTargetDuration != Duration.zero) {
            progress =
                section.elapsedDuration.inSeconds /
                section.adjustedTargetDuration.inSeconds;
          }
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              if (isCurrent || isFinished)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Text(
                        isFinished ? 'Seção Concluída' : 'Seção Atual',
                        style: AppTheme.uiStyle.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isFinished
                              ? AppTheme.accent
                              : AppTheme.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () async {
                            final newDuration = await DurationPickerDialog.show(
                              context,
                              initialDuration: speechController!
                                  .sections[sectionIndex]
                                  .targetDuration,
                              title: 'Meta da Seção',
                            );
                            if (newDuration != null) {
                              speechController!.updateTargetDuration(
                                sectionIndex,
                                newDuration,
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.edit_calendar_rounded,
                                  size: 12,
                                  color: AppTheme.accent,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${_formatDuration(speechController!.sections[sectionIndex].elapsedDuration)} / ${_formatDuration(speechController!.sections[sectionIndex].adjustedTargetDuration)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                    color: isCurrent
                                        ? AppTheme.accent
                                        : AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(
                height: 24,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    // Linha do divisor
                    Container(
                      height: 2,
                      color: isFinished
                          ? AppTheme.accent.withValues(alpha: 0.3)
                          : (isCurrent
                                ? AppTheme.accent.withValues(alpha: 0.3)
                                : AppTheme.border),
                    ),

                    // Barra de progresso (somente se for a seção atual)
                    if (isCurrent)
                      Positioned(
                        left: 0,
                        right: 0,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: progress.clamp(0.0, 1.0),
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              progress > 1.0 ? AppTheme.error : AppTheme.accent,
                            ),
                            minHeight: 4,
                          ),
                        ),
                      ),

                    // Botão de ação
                    if (isCurrent ||
                        isFinished ||
                        speechController!.isSessionFinished)
                      Positioned(
                        right: 0,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (speechController!.isSessionFinished) {
                              onShowSpeechSummary?.call();
                              return;
                            }
                            if (isCurrent) {
                              speechController!.nextSection();
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: speechController!.isSessionFinished
                                  ? Colors.amber.shade700
                                  : AppTheme.accent,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  speechController!.isSessionFinished
                                      ? Icons.assessment_rounded
                                      : (isFinished
                                            ? Icons.check
                                            : Icons.skip_next),
                                  size: 16,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  speechController!.isSessionFinished
                                      ? 'VER RESUMO'
                                      : (isFinished ? 'CONCLUÍDO' : 'PRÓXIMA'),
                                  style: AppTheme.uiStyle.copyWith(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
            ],
          );
      },
    );
  }
}

class FinalizeTimerBuilder extends BlockComponentBuilder {
  final SpeechController? speechController;
  final EditorState editorState;

  FinalizeTimerBuilder({this.speechController, required this.editorState});

  @override
  BlockComponentWidget build(BlockComponentContext blockContext) {
    return FinalizeTimerWidget(
      key: blockContext.node.key,
      node: blockContext.node,
      speechController: speechController,
      editorState: editorState,
    );
  }

  @override
  BlockComponentValidate get validate => (node) => node.type == 'finalize_timer';
}

class FinalizeTimerWidget extends StatelessWidget implements BlockComponentWidget {
  @override
  final Node node;
  final SpeechController? speechController;
  final EditorState editorState;

  const FinalizeTimerWidget({
    super.key,
    required this.node,
    this.speechController,
    required this.editorState,
  });

  @override
  bool get showActions => false;
  @override
  BlockComponentActionBuilder? get actionBuilder => null;
  @override
  BlockComponentActionTrailingBuilder? get actionTrailingBuilder => null;
  @override
  BlockComponentConfiguration get configuration => BlockComponentConfiguration(
        padding: (node) => EdgeInsets.zero,
      );

  @override
  Widget build(BuildContext context) {
    if (speechController == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: speechController!,
      builder: (context, _) {
        final isFinished = speechController!.isSessionFinished;
        return Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: isFinished ? Colors.grey.withValues(alpha: 0.1) : AppTheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(
                  color: isFinished ? Colors.grey : AppTheme.error,
                  width: 2,
                ),
              ),
              child: ElevatedButton.icon(
                onPressed: isFinished ? null : () => speechController!.finishSession(),
                icon: Icon(
                  isFinished ? Icons.check_circle : Icons.stop_circle_outlined,
                  size: 28,
                ),
                label: Text(
                  isFinished ? 'SESSÃO FINALIZADA' : 'FINALIZAR PALESTRA',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isFinished ? Colors.grey : AppTheme.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(38)),
                ),
              ),
            ),
          ),
        ),
          ],
        );
      },
    );
  }
}
