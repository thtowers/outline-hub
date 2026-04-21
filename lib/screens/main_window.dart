import 'package:flutter/material.dart';
import '../widgets/header_bar.dart';
import '../widgets/side_bar.dart';
import '../widgets/document_view.dart';
import '../theme/app_theme.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

class MainWindow extends StatefulWidget {
  const MainWindow({super.key});

  @override
  State<MainWindow> createState() => _MainWindowState();
}

class _MainWindowState extends State<MainWindow> {
  bool _showRightPanel = false;
  String _rightPanelType = '';

  List<String> _openTabs = ['main.dart', 'app.dart'];
  int _activeTabIndex = 0;
  String? _openedFolderName;
  List<Map<String, dynamic>> _folderFiles = [];
  double _sidebarWidth = 250.0;
  final Map<String, String> _fileContents = {};

  void _openFile(String path) {
    setState(() {
      final newTabs = List<String>.from(_openTabs);
      if (!newTabs.contains(path)) {
        newTabs.add(path);
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
      newTabs.removeAt(index);
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
      _activeTabIndex = _openTabs.length - 1;
    });
  }

  Future<void> _handleOpenFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result != null && result.files.single.path != null) {
        String path = result.files.single.path!;
        _openFile(path);
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
    }
  }

  Future<void> _handleOpenFolder() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory != null) {
        setState(() {
          _openedFolderName = selectedDirectory.split('/').last;
          if (_openedFolderName!.isEmpty) _openedFolderName = selectedDirectory;
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
      debugPrint('Error picking directory: $e');
    }
  }

  Future<void> _handleSaveFile() async {
    debugPrint('SAVE BUTTON CLICKED');
    if (_openTabs.isEmpty) return;
    
    String currentPath = _openTabs[_activeTabIndex];
    String content = _fileContents[currentPath] ?? '';
    
    // 1. Show format selection dialog
    String? extension = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose Format'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, '.txt'),
            child: const Row(
              children: [
                Icon(Icons.text_snippet_outlined, size: 20),
                SizedBox(width: 12),
                Text('Text File (.txt)'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, '.md'),
            child: const Row(
              children: [
                Icon(Icons.description_outlined, size: 20),
                SizedBox(width: 12),
                Text('Markdown File (.md)'),
              ],
            ),
          ),
        ],
      ),
    );

    if (extension == null) return; // User cancelled

    String initialName = currentPath.split('/').last;
    // Strip old extension if any
    if (initialName.contains('.')) {
      initialName = initialName.substring(0, initialName.lastIndexOf('.'));
    }
    initialName += extension;

    try {
      debugPrint('Opening save dialog for $extension...');
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save File As',
        fileName: initialName,
        type: FileType.any,
      );

      if (outputFile != null) {
        String finalPath = outputFile;
        // Force the chosen extension if missing
        if (!finalPath.endsWith('.txt') && !finalPath.endsWith('.md')) {
          finalPath += extension;
        }

        final file = File(finalPath);
        await file.writeAsString(content);

        setState(() {
          _openTabs[_activeTabIndex] = finalPath;
          _fileContents[finalPath] = content;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('File saved successfully: $finalPath')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error saving file: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _buildTree(Directory dir) async {
    List<Map<String, dynamic>> tree = [];
    try {
      final List<FileSystemEntity> entities = await dir.list().toList();
      for (var entity in entities) {
        String name = entity.path.split('/').last;
        // Skip heavy or hidden folders
        if (name == 'node_modules' || name == '.git' || name == '.dart_tool') continue;

        bool isFolder = entity is Directory;
        tree.add({
          'name': name,
          'path': entity.path,
          'isFolder': isFolder,
          'children': isFolder ? await _buildTree(entity as Directory) : null,
        });
      }
      // Sort: Folders first, then files
      tree.sort((a, b) {
        if (a['isFolder'] && !b['isFolder']) return -1;
        if (!a['isFolder'] && b['isFolder']) return 1;
        return a['name'].toLowerCase().compareTo(b['name'].toLowerCase());
      });
    } catch (e) {
      // Handle permission errors or deleted folders
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
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          // Top HeaderBar (replaces window title bar on custom desktop builds)
          HeaderBar(
            onSearchToggle: () => _toggleRightPanel('search'),
            onTerminalToggle: () => _toggleRightPanel('terminal'),
            onNewTab: _handleNewTab,
            onSave: _handleSaveFile,
          ),
          const Divider(height: 1),
          // Main Content Area
          Expanded(
            child: Row(
              children: [
                // Left Sidebar (File Explorer)
                SideBar(
                  selectedFile: _openTabs.isNotEmpty
                      ? _openTabs[_activeTabIndex]
                      : '',
                  openTabs: _openTabs,
                  folderName: _openedFolderName,
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
                      color: Colors.black.withOpacity(0.1),
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
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
                    onContentChanged: (path, content) {
                      _fileContents[path] = content;
                    },
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
          const Divider(height: 1),
          _buildStatusBar(),
        ],
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
                InkWell(
                  onTap: () => setState(() => _showRightPanel = false),
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Center(
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

  Widget _buildStatusBar() {
    return Container(
      height: 24,
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Ready',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
          Row(
            children: [
              Text(
                'Line 1, Column 1',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              ),
              const SizedBox(width: 24),
              Text(
                'Dart',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              ),
              const SizedBox(width: 24),
              Text(
                'UTF-8',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
