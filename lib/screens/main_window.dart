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
        if (name == 'node_modules' || name == '.git' || name == '.dart_tool' || name.startsWith('.')) {
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
              onInsertSpacesChanged: (val) => setState(() => _insertSpaces = val),
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
                  child: DocumentView(
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
                    onSectionsChanged: (sections) => _speechController.updateSections(sections),
                    textStyleController: _textStyleController,
                    speechController: _speechController,
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
          if (!_isZenMode) ...[
            const Divider(height: 1),
            _buildStatusBar(),
          ],
        ],
      ),
      // Floating Exit button for Zen Mode
      floatingActionButton: _isZenMode 
        ? FloatingActionButton.small(
            onPressed: () => setState(() => _isZenMode = false),
            backgroundColor: AppTheme.accent,
            tooltip: 'Sair da Tela Cheia',
            child: const Icon(Icons.fullscreen_exit, size: 20, color: Colors.white),
          )
        : null,
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
                  _rightPanelType == 'search' ? 'Search' : 'Terminal',
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
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
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
        
        return Column(
          children: [
            // Total Speech Target Input
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const Icon(Icons.flag_outlined, size: 18),
                  const SizedBox(width: 8),
                  const Text('Duração Total:', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 60,
                    child: TextField(
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'mm:ss',
                      ),
                      onSubmitted: (val) {
                        final parts = val.split(':');
                        if (parts.length == 2) {
                          final mins = int.tryParse(parts[0]) ?? 0;
                          final secs = int.tryParse(parts[1]) ?? 0;
                          _speechController.setTotalSpeechTarget(
                            Duration(minutes: mins, seconds: secs)
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Timer Display
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  Text(
                    _formatDuration(totalElapsed),
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: totalElapsed > _speechController.totalSpeechTarget && _speechController.totalSpeechTarget != Duration.zero
                        ? Colors.red 
                        : AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    'Restante: ${_formatDuration(_speechController.totalSpeechTarget - totalElapsed)}',
                    style: TextStyle(
                      color: (totalElapsed > _speechController.totalSpeechTarget) ? Colors.red : AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            
            // Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  onPressed: _speechController.previousSection,
                  tooltip: 'Seção Anterior',
                ),
                IconButton(
                  icon: Icon(_speechController.isRunning ? Icons.pause : Icons.play_arrow),
                  iconSize: 40,
                  onPressed: _speechController.isRunning 
                    ? _speechController.pauseTimer 
                    : _speechController.startTimer,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: _speechController.nextSection,
                  tooltip: 'Próxima Seção',
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _speechController.resetTimer,
                  tooltip: 'Zerar Cronômetro',
                ),
              ],
            ),
            
            const Divider(),
            
            // Sections List
            Expanded(
              child: ListView.builder(
                itemCount: _speechController.sections.length,
                itemBuilder: (context, index) {
                  final section = _speechController.sections[index];
                  final isCurrent = _speechController.currentSectionIndex == index;
                  final isFinished = index < _speechController.currentSectionIndex;
                  
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isCurrent ? AppTheme.accent.withValues(alpha: 0.1) : null,
                      border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                section.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: isCurrent ? AppTheme.accent : (isFinished ? AppTheme.textSecondary : AppTheme.textPrimary),
                                  decoration: isFinished ? TextDecoration.lineThrough : null,
                                ),
                              ),
                            ),
                            if (isCurrent)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.accent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('AO VIVO', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('Meta: ', style: TextStyle(fontSize: 11)),
                            SizedBox(
                              width: 50,
                              child: TextField(
                                style: const TextStyle(fontSize: 11),
                                decoration: const InputDecoration(isDense: true, border: InputBorder.none, hintText: '00:00'),
                                onSubmitted: (val) {
                                  final parts = val.split(':');
                                  if (parts.length == 2) {
                                    final mins = int.tryParse(parts[0]) ?? 0;
                                    final secs = int.tryParse(parts[1]) ?? 0;
                                    _speechController.updateTargetDuration(index, Duration(minutes: mins, seconds: secs));
                                  }
                                },
                              ),
                            ),
                            if (section.adjustedTargetDuration != section.targetDuration) ...[
                              const SizedBox(width: 8),
                              Text(
                                '(${_formatDuration(section.adjustedTargetDuration)})',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: section.adjustedTargetDuration < section.targetDuration ? Colors.red : Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                            const Spacer(),
                            Text(
                              _formatDuration(section.elapsedDuration),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                                color: section.elapsedDuration > section.adjustedTargetDuration && section.targetDuration != Duration.zero
                                    ? Colors.red 
                                    : (isCurrent ? AppTheme.accent : AppTheme.textSecondary),
                              ),
                            ),
                          ],
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
                _statusMessage == 'Pronto' ? Icons.check_circle_outline : Icons.sync,
                size: 14,
                color: _statusMessage == 'Pronto' ? Colors.green : AppTheme.accent,
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
      title: Text(title, style: TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
      subtitle: Text(value, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      trailing: Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 16),
    );
  }

  Widget _buildShortcutItem(String title, String keys, IconData icon) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.textSecondary, size: 20),
      title: Text(title, style: TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.2)),
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
}
