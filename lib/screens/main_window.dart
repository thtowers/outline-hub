import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/header_bar.dart';
import '../widgets/side_bar.dart';
import '../widgets/document_view.dart';
import '../theme/app_theme.dart';
import '../models/edit_format.dart';
import '../models/note_metadata.dart';
import '../controllers/text_style_controller.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../controllers/speech_controller.dart';
import '../widgets/duration_picker_dialog.dart';

class MainWindow extends StatefulWidget {
  const MainWindow({super.key});

  @override
  State<MainWindow> createState() => _MainWindowState();
}

class _MainWindowState extends State<MainWindow> {
  bool _showRightPanel = false;
  String _rightPanelType = '';
  bool _isZenMode = false;

  List<String> _openTabs = [];
  int _activeTabIndex = 0;
  String? _openedFolderName;
  String? _openedFolderPath;
  List<Map<String, dynamic>> _folderFiles = [];
  double _sidebarWidth = 250.0;
  final Map<String, String> _fileContents = {};
  final Map<String, EditFormat> _tabFormats = {};
  final Map<String, NoteMetadata> _noteMetadataMap = {};

  // Tab settings
  int _tabWidth = 2;
  bool _autoIndent = true;
  bool _insertSpaces = true;

  // Status Info
  int _line = 1;
  int _column = 1;
  String _statusMessage = 'Pronto';
  String _encoding = 'UTF-8';
  final _textStyleController = TextStyleController();
  final _speechController = SpeechController();

  void _updatePosition(int line, int column) {
    setState(() {
      _line = line;
      _column = column;
    });
  }

  void _openFile(String path) {
    setState(() {
      final newTabs = List<String>.from(_openTabs);
      if (!newTabs.contains(path)) {
        newTabs.add(path);
        _tabFormats[path] = EditFormat.fromPath(path);
        _activeTabIndex = newTabs.length - 1;
      } else {
        _activeTabIndex = newTabs.indexOf(path);
      }
      _openTabs = newTabs;
    });
  }

  void _closeTab(int index) {
    setState(() {
      final newTabs = List<String>.from(_openTabs);
      final String removedPath = newTabs.removeAt(index);
      _tabFormats.remove(removedPath);

      if (index < _activeTabIndex) {
        _activeTabIndex--;
      } else if (index == _activeTabIndex) {
        if (newTabs.isEmpty) {
          _activeTabIndex = 0;
        } else if (_activeTabIndex >= newTabs.length) {
          _activeTabIndex = newTabs.length - 1;
        }
      }
      _openTabs = newTabs;
    });
  }

  void _selectTab(int index) {
    setState(() {
      _activeTabIndex = index;
    });
  }

  void _handleNewTab() {
    setState(() {
      int counter = 1;
      String newName = 'Untitled-$counter';
      while (_openTabs.contains(newName)) {
        counter++;
        newName = 'Untitled-$counter';
      }
      _openTabs.add(newName);
      _tabFormats[newName] = EditFormat.markdown;
      _activeTabIndex = _openTabs.length - 1;
    });
  }

  void _toggleSpeechPanel() {
    setState(() {
      if (_showRightPanel && _rightPanelType == 'speech') {
        _showRightPanel = false;
      } else {
        _showRightPanel = true;
        _rightPanelType = 'speech';
      }
    });
  }

  Future<void> _handleOpenFile() async {
    if (_isPicking) return;
    _isPicking = true;
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result != null && result.files.single.path != null) {
        String path = result.files.single.path!;
        _openFile(path);
      }
    } catch (e) {
      debugPrint('DocumentView: Error picking file: $e');
    } finally {
      _isPicking = false;
    }
  }

  bool _isPicking = false;
  Future<void> _handleOpenFolder() async {
    if (_isPicking) {
      debugPrint('DocumentView: Already picking a folder, ignoring request.');
      return;
    }

    _isPicking = true;
    debugPrint('DocumentView: Requesting directory path from FilePicker...');

    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      debugPrint('DocumentView: FilePicker returned: $selectedDirectory');

      if (selectedDirectory != null) {
        setState(() {
          _openedFolderName = selectedDirectory.split('/').last;
          if (_openedFolderName!.isEmpty) _openedFolderName = selectedDirectory;
          _openedFolderPath = selectedDirectory;
        });

        // Build the tree recursively
        final tree = await _buildTree(Directory(selectedDirectory));

        setState(() {
          _folderFiles = tree;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Opened folder: $selectedDirectory')),
          );
        }
      }
    } catch (e) {
      debugPrint('DocumentView: Error picking directory: $e');
    } finally {
      _isPicking = false;
      debugPrint('DocumentView: Directory picking process finished.');
    }
  }

  Future<void> _handleSaveFile() async {
    debugPrint('SAVE BUTTON CLICKED');
    if (_openTabs.isEmpty) return;

    setState(() {
      _statusMessage = 'Salvando...';
    });

    String currentPath = _openTabs[_activeTabIndex];
    String content = _fileContents[currentPath] ?? '';

    // 1. Show format selection dialog
    EditFormat? chosenFormat = await showDialog<EditFormat>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Escolher Formato'),
        children: EditFormat.values.map((format) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, format),
            child: Row(
              children: [
                Icon(_getFormatIcon(format), size: 20),
                const SizedBox(width: 12),
                Text('${format.label} (${format.extension})'),
              ],
            ),
          );
        }).toList(),
      ),
    );

    if (chosenFormat == null) {
      setState(() {
        _statusMessage = 'Pronto';
      });
      return;
    } // User cancelled
    String extension = chosenFormat.extension;

    String initialName = currentPath.split('/').last;
    // Strip old extension if any
    if (initialName.contains('.')) {
      initialName = initialName.substring(0, initialName.lastIndexOf('.'));
    }
    initialName += extension;

    try {
      debugPrint('Opening save dialog for $extension...');
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Salvar Arquivo Como',
        fileName: initialName,
        type: FileType.any,
      );

      if (outputFile != null) {
        String finalPath = outputFile;
        // Force the chosen extension if missing
        if (!finalPath.endsWith(extension)) {
          finalPath += extension;
        }

        final file = File(finalPath);
        await file.writeAsString(content);

        setState(() {
          _openTabs[_activeTabIndex] = finalPath;
          _fileContents[finalPath] = content;
          _statusMessage = 'Pronto';
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Arquivo salvo com sucesso: $finalPath')),
          );
        }
      } else {
        setState(() {
          _statusMessage = 'Pronto';
        });
      }
    } catch (e) {
      debugPrint('Error saving file: $e');
      setState(() {
        _statusMessage = 'Erro ao salvar';
      });
    }
  }

  Future<List<Map<String, dynamic>>> _buildTree(Directory dir) async {
    List<Map<String, dynamic>> tree = [];
    try {
      final List<FileSystemEntity> entities = await dir.list().toList();
      for (var entity in entities) {
        String name = entity.path.split('/').last;
        // Skip heavy or hidden folders
        if (name == 'node_modules' ||
            name == '.git' ||
            name == '.dart_tool' ||
            name.startsWith('.')) {
          continue;
        }

        bool isFolder = entity is Directory;
        tree.add({
          'name': name,
          'path': entity.path,
          'isFolder': isFolder,
          'children': null, // Do not load children recursively
        });
      }
      // Sort: Folders first, then files
      tree.sort((a, b) {
        if (a['isFolder'] && !b['isFolder']) return -1;
        if (!a['isFolder'] && b['isFolder']) return 1;
        return a['name'].toLowerCase().compareTo(b['name'].toLowerCase());
      });
    } catch (e) {
      debugPrint('Error building tree: $e');
    }
    return tree;
  }

  void _reorderTab(int oldIndex, int newIndex) {
    setState(() {
      final newTabs = List<String>.from(_openTabs);
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final String item = newTabs.removeAt(oldIndex);
      newTabs.insert(newIndex, item);

      // Adjust _activeTabIndex logically
      if (_activeTabIndex == oldIndex) {
        _activeTabIndex = newIndex;
      } else if (_activeTabIndex > oldIndex && _activeTabIndex <= newIndex) {
        _activeTabIndex--;
      } else if (_activeTabIndex < oldIndex && _activeTabIndex >= newIndex) {
        _activeTabIndex++;
      }

      _openTabs = newTabs;
    });
  }

  void _toggleRightPanel(String type) {
    setState(() {
      if (_showRightPanel && _rightPanelType == type) {
        _showRightPanel = false;
      } else {
        _showRightPanel = true;
        _rightPanelType = type;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        if (_isZenMode && event.logicalKey == LogicalKeyboardKey.escape) {
          setState(() => _isZenMode = false);
        }

        // Atalho Alt + D para Divisor
        if (event is KeyDownEvent &&
            HardwareKeyboard.instance.isAltPressed &&
            event.logicalKey == LogicalKeyboardKey.keyD) {
          _textStyleController.insertDivider();
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Column(
          children: [
            // Top HeaderBar (replaces window title bar on custom desktop builds)
            // Top HeaderBar (replaces window title bar on custom desktop builds)
            if (!_isZenMode) ...[
              HeaderBar(
                onSearchToggle: () => _toggleRightPanel('search'),
                onTerminalToggle: () => _toggleRightPanel('terminal'),
                onNewTab: _handleNewTab,
                onSave: _handleSaveFile,
                onOpenFolder: _handleOpenFolder,
                onOpenFile: _handleOpenFile,
                tabWidth: _tabWidth,
                autoIndent: _autoIndent,
                insertSpaces: _insertSpaces,
                currentFormat: _openTabs.isNotEmpty
                    ? _tabFormats[_openTabs[_activeTabIndex]] ?? EditFormat.txt
                    : EditFormat.txt,
                onTabWidthChanged: (val) => setState(() => _tabWidth = val),
                onAutoIndentChanged: (val) => setState(() => _autoIndent = val),
                onInsertSpacesChanged: (val) =>
                    setState(() => _insertSpaces = val),
                onFormatChanged: (format) {
                  if (_openTabs.isNotEmpty) {
                    setState(() {
                      _tabFormats[_openTabs[_activeTabIndex]] = format;
                    });
                  }
                },
                textStyleController: _textStyleController,
                onZenModeToggle: () => setState(() => _isZenMode = !_isZenMode),
                onSettingsToggle: _showSettingsDialog,
                onSpeechToggle: _toggleSpeechPanel,
              ),
              const Divider(height: 1),
            ],
            // Main Content Area
            Expanded(
              child: Row(
                children: [
                  // Left Sidebar (File Explorer)
                  if (!_isZenMode) ...[
                    SideBar(
                      selectedFile: _openTabs.isNotEmpty
                          ? _openTabs[_activeTabIndex]
                          : '',
                      openTabs: _openTabs,
                      folderName: _openedFolderName,
                      folderPath: _openedFolderPath,
                      folderFiles: _folderFiles,
                      width: _sidebarWidth,
                      onFileSelected: _openFile,
                    ),
                    // Resizable Divider
                    MouseRegion(
                      cursor: SystemMouseCursors.resizeLeftRight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragUpdate: (details) {
                          setState(() {
                            _sidebarWidth += details.delta.dx;
                            // Constraints
                            if (_sidebarWidth < 120) _sidebarWidth = 120;
                            if (_sidebarWidth > 600) _sidebarWidth = 600;
                          });
                        },
                        child: Container(
                          width: 4,
                          color: Colors.black.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                  ],
                  // Center Document View
                  Expanded(
                    child: Stack(
                      children: [
                        DocumentView(
                          tabs: _openTabs,
                          activeTabIndex: _activeTabIndex,
                          fileContents: _fileContents,
                          onCloseTab: _closeTab,
                          onSelectTab: _selectTab,
                          onReorderTab: _reorderTab,
                          onNewTab: _handleNewTab,
                          onOpenFile: _handleOpenFile,
                          onOpenFolder: _handleOpenFolder,
                          onSaveFile: _handleSaveFile,
                          tabWidth: _tabWidth,
                          autoIndent: _autoIndent,
                          insertSpaces: _insertSpaces,
                          noteMetadataMap: _noteMetadataMap,
                          onMetadataChanged: (path, meta) {
                            setState(() => _noteMetadataMap[path] = meta);
                          },
                          currentFormat: _openTabs.isNotEmpty
                              ? _tabFormats[_openTabs[_activeTabIndex]]
                              : null,
                          onContentChanged: (path, content) {
                            _fileContents[path] = content;
                          },
                          onPositionChanged: _updatePosition,
                          onSectionsChanged: (sections) =>
                              _speechController.updateSections(sections),
                          textStyleController: _textStyleController,
                          speechController: _speechController,
                          onShowSpeechSummary: () {
                            setState(() {
                              _showRightPanel = true;
                              _rightPanelType = 'speech';
                            });
                          },
                        ),
                        if (_isZenMode)
                          Positioned(
                            bottom: 24,
                            right: 24,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FloatingActionButton.small(
                                  heroTag: 'speech_toggle',
                                  onPressed: _toggleSpeechPanel,
                                  backgroundColor: _showRightPanel &&
                                          _rightPanelType == 'speech'
                                      ? AppTheme.accent
                                      : AppTheme.surface,
                                  tooltip: 'Cronômetro',
                                  child: Icon(
                                    Icons.timer_outlined,
                                    size: 20,
                                    color: _showRightPanel &&
                                            _rightPanelType == 'speech'
                                        ? Colors.white
                                        : AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                FloatingActionButton.small(
                                  heroTag: 'exit_zen',
                                  onPressed: () =>
                                      setState(() => _isZenMode = false),
                                  backgroundColor: AppTheme.accent,
                                  tooltip: 'Sair da Tela Cheia',
                                  child: const Icon(
                                    Icons.fullscreen_exit,
                                    size: 20,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_showRightPanel) ...[
                    const VerticalDivider(width: 1),
                    _buildRightPanel(),
                  ],
                ],
              ),
            ),
            // Bottom Status Bar
            if (!_isZenMode) ...[const Divider(height: 1), _buildStatusBar()],
          ],
        ),
      ),
    );
  }

  Widget _buildRightPanel() {
    return Container(
      width: 250,
      color: AppTheme.sidebarBackground,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: AppTheme.surface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _rightPanelType == 'search' ? 'Pesquisa' : 'Cronômetro',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Tooltip(
                  message: 'Fechar Painel',
                  child: InkWell(
                    onTap: () => setState(() => _showRightPanel = false),
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _rightPanelType == 'speech'
                ? _buildSpeechPanel()
                : Center(
                    child: Text(
                      _rightPanelType == 'search'
                          ? 'Search panel...'
                          : 'Terminal ready...',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeechPanel() {
    return ListenableBuilder(
      listenable: _speechController,
      builder: (context, _) {
        final totalElapsed = _speechController.totalElapsed;
        final isOvertime =
            totalElapsed > _speechController.totalSpeechTarget &&
            _speechController.totalSpeechTarget != Duration.zero;

        return Column(
          children: [
            // Header / Total Duration
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.surface,
                    AppTheme.surface.withValues(alpha: 0.8),
                  ],
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'CRONÔMETRO TOTAL',
                        style: AppTheme.uiStyle.copyWith(
                          color: AppTheme.textSecondary,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      GestureDetector(
                        onTap: () async {
                          final newDuration = await DurationPickerDialog.show(
                            context,
                            initialDuration:
                                _speechController.totalSpeechTarget,
                            title: 'Duração Total da Palestra',
                          );
                          if (newDuration != null) {
                            _speechController.setTotalSpeechTarget(newDuration);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.background,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: AppTheme.border,
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.edit_outlined, size: 10),
                              const SizedBox(width: 4),
                              Text(
                                _formatDuration(
                                  _speechController.totalSpeechTarget,
                                ),
                                style: AppTheme.uiStyle.copyWith(
                                  fontSize: 10,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatDuration(totalElapsed),
                    style: AppTheme.uiStyle.copyWith(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -1.5,
                      color: isOvertime ? AppTheme.error : AppTheme.textPrimary,
                    ),
                  ),
                  if (_speechController.totalSpeechTarget != Duration.zero)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: (isOvertime ? AppTheme.error : AppTheme.accent)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isOvertime
                            ? 'ATRAZADO: -${_formatDuration(totalElapsed - _speechController.totalSpeechTarget)}'
                            : 'SALDO: +${_formatDuration(_speechController.totalSpeechTarget - totalElapsed)}',
                        style: AppTheme.uiStyle.copyWith(
                          color: isOvertime ? AppTheme.error : AppTheme.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Main Controls
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildLargeControlButton(
                    icon: Icons.replay_rounded,
                    onPressed: _speechController.restartCurrentSection,
                    color: AppTheme.textSecondary,
                    isSmall: true,
                    tooltip: 'Reiniciar Seção',
                  ),
                  _buildLargeControlButton(
                    icon: Icons.skip_previous_rounded,
                    onPressed: _speechController.previousSection,
                    color: AppTheme.textPrimary,
                    tooltip: 'Seção Anterior',
                  ),
                  _buildPlayPauseButton(),
                  _buildLargeControlButton(
                    icon: Icons.skip_next_rounded,
                    onPressed: _speechController.nextSection,
                    color: AppTheme.textPrimary,
                    tooltip: 'Próxima Seção',
                  ),
                  _buildLargeControlButton(
                    icon: Icons.refresh_rounded,
                    onPressed: _speechController.resetTimer,
                    color: AppTheme.textSecondary,
                    isSmall: true,
                    tooltip: 'Zerar Tudo',
                  ),
                ],
              ),
            ),

            // Finalize Button
            if (!_speechController.isSessionFinished)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _speechController.finishSession,
                    icon: const Icon(Icons.stop_circle_rounded, size: 20),
                    label: const Text('FINALIZAR'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.error.withValues(alpha: 0.1),
                      foregroundColor: AppTheme.error,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: AppTheme.error.withValues(alpha: 0.3),
                        ),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 8),
            const Divider(height: 1),

            // Sections List or Summary Report
            Expanded(
              child: _speechController.isSessionFinished
                  ? _buildSpeechSummary()
                  : CallbackShortcuts(
                      bindings: {
                        const SingleActivator(LogicalKeyboardKey.f2): () {
                          if (!_speechController.isSessionFinished) {
                            final index = _speechController.currentSectionIndex;
                            _showRenameDialog(
                              index,
                              _speechController.sections[index].title,
                            );
                          }
                        },
                      },
                      child: Focus(
                        autofocus: true,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _speechController.sections.length,
                          itemBuilder: (context, index) {
                            final section = _speechController.sections[index];
                            final isCurrent =
                                _speechController.currentSectionIndex == index;
                            final isFinished =
                                index < _speechController.currentSectionIndex;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? AppTheme.accent.withValues(alpha: 0.05)
                                    : AppTheme.surface.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isCurrent
                                      ? AppTheme.accent.withValues(alpha: 0.3)
                                      : Colors.transparent,
                                  width: 1,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: isFinished
                                                ? AppTheme.accent
                                                : (isCurrent
                                                      ? AppTheme.accent
                                                      : AppTheme.background),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: isFinished
                                                ? const Icon(
                                                    Icons.check,
                                                    size: 14,
                                                    color: Colors.white,
                                                  )
                                                : Text(
                                                    '${index + 1}',
                                                    style: AppTheme.uiStyle
                                                        .copyWith(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: isCurrent
                                                              ? Colors.white
                                                              : AppTheme
                                                                    .textSecondary,
                                                        ),
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: InkWell(
                                            onTap: () => _showRenameDialog(
                                              index,
                                              section.title,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 2,
                                                  ),
                                              child: Text(
                                                section.title,
                                                style: AppTheme.uiStyle
                                                    .copyWith(
                                                      fontWeight: isCurrent
                                                          ? FontWeight.bold
                                                          : FontWeight.w500,
                                                      fontSize: 14,
                                                      color: isFinished
                                                          ? AppTheme
                                                                .textSecondary
                                                          : AppTheme
                                                                .textPrimary,
                                                      decoration: isFinished
                                                          ? TextDecoration
                                                                .lineThrough
                                                          : null,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            if (isFinished || isCurrent)
                                              _buildDifferenceBadge(
                                                section.adjustedTargetDuration -
                                                    section.elapsedDuration,
                                              ),
                                            if (isCurrent) ...[
                                              const SizedBox(height: 4),
                                              _buildLiveIndicator(),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              onTap: () async {
                                                final newDuration =
                                                    await DurationPickerDialog.show(
                                                      context,
                                                      initialDuration: section
                                                          .targetDuration,
                                                      title: 'Meta da Seção',
                                                    );
                                                if (newDuration != null) {
                                                  _speechController
                                                      .updateTargetDuration(
                                                        index,
                                                        newDuration,
                                                      );
                                                }
                                              },
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.background
                                                      .withValues(alpha: 0.5),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: AppTheme.border
                                                        .withValues(alpha: 0.5),
                                                  ),
                                                ),
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      const Icon(
                                                        Icons
                                                            .edit_calendar_rounded,
                                                        size: 14,
                                                        color: AppTheme.accent,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        'Meta: ${_formatDuration(section.targetDuration)}',
                                                        style: AppTheme.uiStyle
                                                            .copyWith(
                                                              fontSize: 11,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: AppTheme
                                                                  .textPrimary,
                                                            ),
                                                      ),
                                                      if (section
                                                              .adjustedTargetDuration !=
                                                          section
                                                              .targetDuration) ...[
                                                        const SizedBox(
                                                          width: 2,
                                                        ),
                                                        Text(
                                                          '→${_formatDuration(section.adjustedTargetDuration)}',
                                                          style: AppTheme
                                                              .uiStyle
                                                              .copyWith(
                                                                fontSize: 11,
                                                                color:
                                                                    section.adjustedTargetDuration <
                                                                        section
                                                                            .targetDuration
                                                                    ? AppTheme
                                                                          .error
                                                                    : AppTheme
                                                                          .accent,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _formatDuration(
                                            section.elapsedDuration,
                                          ),
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'monospace',
                                            color:
                                                section.elapsedDuration >
                                                        section
                                                            .adjustedTargetDuration &&
                                                    section.targetDuration !=
                                                        Duration.zero
                                                ? AppTheme.error
                                                : (isCurrent
                                                      ? AppTheme.accent
                                                      : AppTheme.textSecondary),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDifferenceBadge(Duration difference) {
    final isPositive = difference >= Duration.zero;
    final absDiff = difference.abs();
    final color = isPositive ? AppTheme.accent : AppTheme.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${isPositive ? '+' : '-'}${_formatDuration(absDiff)}',
        style: AppTheme.uiStyle.copyWith(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildLiveIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.error,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'AGORA',
        style: AppTheme.uiStyle.copyWith(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildLargeControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    required Color color,
    bool isSmall = false,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: EdgeInsets.all(isSmall ? 6 : 8),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: Icon(icon, size: isSmall ? 18 : 22, color: color),
        ),
      ),
    );
  }

  Widget _buildPlayPauseButton() {
    final isRunning = _speechController.isRunning;
    return InkWell(
      onTap: isRunning
          ? _speechController.pauseTimer
          : _speechController.startTimer,
      borderRadius: BorderRadius.circular(40),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.accent,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppTheme.accent.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 28,
          color: Colors.white,
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  void _showFormatSelectionDialog() {
    if (_openTabs.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Select Format'),
          children: EditFormat.values.map((format) {
            return SimpleDialogOption(
              onPressed: () {
                setState(() {
                  _tabFormats[_openTabs[_activeTabIndex]] = format;
                });
                Navigator.pop(context);
              },
              child: Row(
                children: [
                  Icon(_getFormatIcon(format), size: 20),
                  const SizedBox(width: 12),
                  Text(format.label),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  IconData _getFormatIcon(EditFormat format) {
    switch (format) {
      case EditFormat.markdown:
        return Icons.description_outlined;
      case EditFormat.txt:
        return Icons.text_snippet_outlined;
    }
  }

  Widget _buildStatusBar() {
    return Container(
      height: 24,
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                _statusMessage == 'Pronto'
                    ? Icons.check_circle_outline
                    : Icons.sync,
                size: 14,
                color: _statusMessage == 'Pronto'
                    ? Colors.green
                    : AppTheme.accent,
              ),
              const SizedBox(width: 8),
              Text(
                _statusMessage,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                'Lin $_line, Col $_column',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              ),
              const SizedBox(width: 24),
              InkWell(
                onTap: () {
                  _showFormatSelectionDialog();
                },
                child: Text(
                  _openTabs.isNotEmpty
                      ? (_tabFormats[_openTabs[_activeTabIndex]]?.label ??
                            'Texto Simples')
                      : 'Texto Simples',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                ),
              ),
              const SizedBox(width: 24),
              InkWell(
                onTap: _showEncodingSelectionDialog,
                child: Text(
                  _encoding,
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return DefaultTabController(
          length: 2,
          child: AlertDialog(
            backgroundColor: AppTheme.surface,
            title: Text(
              'Configurações',
              style: TextStyle(color: AppTheme.textPrimary),
            ),
            content: SizedBox(
              width: 500,
              height: 400,
              child: Column(
                children: [
                  TabBar(
                    indicatorColor: AppTheme.accent,
                    labelColor: AppTheme.accent,
                    unselectedLabelColor: AppTheme.textSecondary,
                    tabs: const [
                      Tab(text: 'Geral'),
                      Tab(text: 'Atalhos'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Aba Geral
                        ListView(
                          children: [
                            _buildSettingItem(
                              'Tema',
                              'Escuro (Padrão)',
                              Icons.palette_outlined,
                            ),
                            _buildSettingItem(
                              'Auto-salvamento',
                              'Ativado (a cada 30s)',
                              Icons.save_outlined,
                            ),
                          ],
                        ),
                        // Aba Atalhos
                        ListView(
                          children: [
                            _buildShortcutItem(
                              'Inserir Linha (Divisor)',
                              'Alt + D',
                              Icons.horizontal_rule,
                            ),
                            _buildShortcutItem(
                              'Modo Zen (Tela Cheia)',
                              'Esc para Sair',
                              Icons.fullscreen_exit,
                            ),
                            _buildShortcutItem(
                              'Salvar Arquivo',
                              'Ctrl + S',
                              Icons.save,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Fechar', style: TextStyle(color: AppTheme.accent)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSettingItem(String title, String value, IconData icon) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.textSecondary, size: 20),
      title: Text(
        title,
        style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
      ),
      subtitle: Text(
        value,
        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: AppTheme.textSecondary,
        size: 16,
      ),
    );
  }

  Widget _buildShortcutItem(String title, String keys, IconData icon) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.textSecondary, size: 20),
      title: Text(
        title,
        style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: AppTheme.textSecondary.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          keys,
          style: TextStyle(
            color: AppTheme.accent,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  Widget _buildSpeechSummary() {
    final sections = _speechController.sections;
    final totalElapsed = _speechController.totalElapsed;
    final totalTarget = _speechController.totalSpeechTarget;
    final diff = totalTarget - totalElapsed;
    final isFast = diff >= Duration.zero;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Report Header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border.withValues(alpha: 0.5)),
          ),
          child: Column(
            children: [
              Icon(
                isFast ? Icons.emoji_events_rounded : Icons.timer_outlined,
                size: 48,
                color: isFast ? Colors.amber : AppTheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                'Resumo da Palestra',
                style: AppTheme.uiStyle.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isFast
                    ? 'Parabéns! Você terminou com ${_formatDuration(diff)} de sobra!'
                    : 'Atenção! Você excedeu o tempo total em ${_formatDuration(diff.abs())}.',
                textAlign: TextAlign.center,
                style: AppTheme.uiStyle.copyWith(
                  color: isFast ? AppTheme.accent : AppTheme.error,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        Text(
          'DESEMPENHO POR SEÇÃO',
          style: AppTheme.uiStyle.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: AppTheme.textSecondary,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),

        ...List.generate(sections.length, (index) {
          final s = sections[index];
          final sDiff = s.adjustedTargetDuration - s.elapsedDuration;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surface.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: AppTheme.background,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        'Meta: ${_formatDuration(s.targetDuration)} | Real: ${_formatDuration(s.elapsedDuration)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildDifferenceBadge(sDiff),
              ],
            ),
          );
        }),

        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _speechController.resetTimer,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('INICIAR NOVA REPETIÇÃO'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              side: BorderSide(color: AppTheme.accent.withValues(alpha: 0.5)),
              foregroundColor: AppTheme.accent,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _exportSummaryToMarkdown,
            icon: const Icon(Icons.download_rounded),
            label: const Text('SALVAR RESUMO (.MD)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  String _generateSummaryMarkdown() {
    final sections = _speechController.sections;
    final totalElapsed = _speechController.totalElapsed;
    final totalTarget = _speechController.totalSpeechTarget;
    final diff = totalTarget - totalElapsed;
    final isFast = diff >= Duration.zero;

    StringBuffer sb = StringBuffer();
    sb.writeln('# Resumo da Palestra');
    sb.writeln('**Data:** ${DateTime.now().toString().split('.').first}');
    sb.writeln();
    sb.writeln('## Resultado Geral');
    sb.writeln(
      '* **Status:** ${isFast ? "✅ Dentro do Tempo" : "⚠️ Excedeu o Tempo"}',
    );
    sb.writeln('* **Tempo Total Planejado:** ${_formatDuration(totalTarget)}');
    sb.writeln('* **Tempo Total Realizado:** ${_formatDuration(totalElapsed)}');
    sb.writeln(
      '* **Saldo:** ${isFast ? "+" : "-"}${_formatDuration(diff.abs())}',
    );
    sb.writeln();
    sb.writeln('## Detalhamento por Seção');
    sb.writeln('| # | Seção | Planejado | Realizado | Diferença |');
    sb.writeln('|---|-------|-----------|-----------|-----------|');

    for (int i = 0; i < sections.length; i++) {
      final s = sections[i];
      final sDiff = s.adjustedTargetDuration - s.elapsedDuration;
      final sIsFast = sDiff >= Duration.zero;
      sb.writeln(
        '| ${i + 1} | ${s.title} | ${_formatDuration(s.targetDuration)} | ${_formatDuration(s.elapsedDuration)} | ${sIsFast ? "+" : "-"}${_formatDuration(sDiff.abs())} |',
      );
    }

    return sb.toString();
  }

  Future<void> _exportSummaryToMarkdown() async {
    final content = _generateSummaryMarkdown();
    final timestamp = DateTime.now()
        .toString()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final fileName = 'Resumo_Palestra_$timestamp.md';

    try {
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Salvar Resumo da Palestra',
        fileName: fileName,
        type: FileType.any,
      );

      if (outputFile != null) {
        String finalPath = outputFile;
        if (!finalPath.endsWith('.md')) {
          finalPath += '.md';
        }

        final file = File(finalPath);
        await file.writeAsString(content);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Resumo exportado com sucesso: $finalPath')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao salvar resumo: $e')));
      }
    }
  }

  void _showEncodingSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Selecionar Codificação'),
        children: ['UTF-8', 'ISO-8859-1', 'Windows-1252', 'ASCII'].map((enc) {
          return SimpleDialogOption(
            onPressed: () {
              setState(() => _encoding = enc);
              Navigator.pop(context);
            },
            child: Text(enc),
          );
        }).toList(),
      ),
    );
  }

  void _showRenameDialog(int index, String currentTitle) {
    final controller = TextEditingController(text: currentTitle);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renomear Seção'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nome da seção'),
          onSubmitted: (value) {
            if (value.isNotEmpty) {
              _speechController.renameSection(index, value);
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                _speechController.renameSection(index, controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text('SALVAR'),
          ),
        ],
      ),
    );
  }
}
