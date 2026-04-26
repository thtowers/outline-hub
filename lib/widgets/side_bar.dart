import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import '../theme/app_theme.dart';

class SideBar extends StatefulWidget {
  final String selectedFile;
  final List<String> openTabs;
  final List<Map<String, dynamic>> folderFiles;
  final String? folderName;
  final String? folderPath;
  final double width;
  final Function(String) onFileSelected;
  final Function(String?) onFolderSelected;
  final Function(String?) onFolderCreated;
  final Function(String, String) onRenamed;
  final Function(String oldPath, String newParentPath) onMove;
  final Function(String path, bool isFolder) onDeleted;
  final Function(String path) onCopy;
  final Function(String targetFolder) onPaste;
  final VoidCallback? onRefresh;

  const SideBar({
    super.key,
    required this.selectedFile,
    required this.openTabs,
    required this.folderFiles,
    this.folderName,
    this.folderPath,
    required this.width,
    required this.onFileSelected,
    required this.onFolderSelected,
    required this.onFolderCreated,
    required this.onRenamed,
    required this.onMove,
    required this.onDeleted,
    required this.onCopy,
    required this.onPaste,
    this.onRefresh,
  });

  @override
  State<SideBar> createState() => _SideBarState();
}

class _SideBarState extends State<SideBar> {
  final Set<String> _expandedFolders = {};
  final Map<String, List<Map<String, dynamic>>> _subFolderCache = {};
  String? _selectedPath;
  String? _editingPath;
  late TextEditingController _renameController;
  late FocusNode _renameFocusNode;
  final FocusNode _sidebarFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _renameController = TextEditingController();
    _renameFocusNode = FocusNode();
    _selectedPath = widget.selectedFile.isEmpty ? null : widget.selectedFile;
  }

  @override
  void didUpdateWidget(SideBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedFile != oldWidget.selectedFile) {
      setState(() {
        _selectedPath = widget.selectedFile.isEmpty ? null : widget.selectedFile;
      });
    }
    // Update cache if main folder files changed (e.g. after a move)
    if (widget.folderFiles != oldWidget.folderFiles) {
      _subFolderCache.clear();
      for (final folder in _expandedFolders) {
        if (Directory(folder).existsSync()) {
          _loadSubFolder(folder, '');
        }
      }
    }
  }

  @override
  void dispose() {
    _renameController.dispose();
    _renameFocusNode.dispose();
    _sidebarFocusNode.dispose();
    super.dispose();
  }

  void _startEditing(String path, String currentName) {
    setState(() {
      _editingPath = path;
      _renameController.text = currentName;
      _renameFocusNode.requestFocus();
    });
  }

  void _submitRename() {
    if (_editingPath != null && _renameController.text.isNotEmpty) {
      widget.onRenamed(_editingPath!, _renameController.text);
    }
    setState(() {
      _editingPath = null;
    });
  }

  Future<void> _loadSubFolder(String path, String label) async {
    if (_subFolderCache.containsKey(path)) return;

    try {
      final dir = Directory(path);
      final List<FileSystemEntity> entities = await dir.list().toList();
      List<Map<String, dynamic>> children = [];

      for (var entity in entities) {
        String name = entity.path.split('/').last;
        if (name == 'node_modules' ||
            name == '.git' ||
            name == '.dart_tool' ||
            name.startsWith('.')) {
          continue;
        }
        children.add({
          'name': name,
          'path': entity.path,
          'isFolder': entity is Directory,
          'children': null,
        });
      }

      children.sort((a, b) {
        if (a['isFolder'] && !b['isFolder']) return -1;
        if (!a['isFolder'] && b['isFolder']) return 1;
        return a['name'].toLowerCase().compareTo(b['name'].toLowerCase());
      });

      if (mounted) {
        setState(() {
          _subFolderCache[path] = children;
        });
      }
    } catch (e) {
      debugPrint('Error loading subfolder: $e');
    }
  }

  void _showContextMenu(
    BuildContext context,
    Offset globalPosition,
    String? path,
    bool isFolder,
  ) async {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
      Offset.zero & overlay.size,
    );

    final String? action = await showMenu<String>(
      context: context,
      position: position,
      color: AppTheme.sidebarBackground,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem(
          value: 'open_location',
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 18, color: AppTheme.textPrimary),
              const SizedBox(width: 12),
              Text(
                'Abrir na pasta',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              ),
            ],
          ),
        ),
        if (isFolder || path == null)
          PopupMenuItem(
            value: 'new_folder',
            child: Row(
              children: [
                Icon(
                  Icons.create_new_folder_outlined,
                  size: 18,
                  color: AppTheme.textPrimary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Nova Pasta',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                ),
              ],
            ),
          ),
        if (path != null)
          PopupMenuItem(
            value: 'copy',
            child: Row(
              children: [
                Icon(Icons.copy, size: 18, color: AppTheme.textPrimary),
                const SizedBox(width: 12),
                Text(
                  'Copiar',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                ),
              ],
            ),
          ),
        if (isFolder || path == null)
          PopupMenuItem(
            value: 'paste',
            child: Row(
              children: [
                Icon(Icons.paste, size: 18, color: AppTheme.textPrimary),
                const SizedBox(width: 12),
                Text(
                  'Colar',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                ),
              ],
            ),
          ),
        if (path != null && path != widget.folderPath)
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                const SizedBox(width: 12),
                Text(
                  'Remover',
                  style: TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ],
            ),
          ),
      ],
    );

    if (action == 'rename') {
      if (path != null) {
        _startEditing(path, path.split('/').last);
      }
    } else if (action == 'new_folder') {
      widget.onFolderCreated(path);
    } else if (action == 'open_location') {
      if (path == null) return;
      final String dirPath = isFolder ? path : File(path).parent.path;
      final Uri uri = Uri.directory(dirPath);

      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not open folder location')),
            );
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    } else if (action == 'delete') {
      if (path != null) {
        widget.onDeleted(path, isFolder);
      }
    } else if (action == 'copy') {
      if (path != null) {
        widget.onCopy(path);
      }
    } else if (action == 'paste') {
      String target = path ?? widget.folderPath ?? '';
      if (target.isNotEmpty) {
        if (File(target).existsSync()) {
          target = File(target).parent.path;
        }
        widget.onPaste(target);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _sidebarFocusNode,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          final isControlPressed = HardwareKeyboard.instance.isControlPressed;

          if (event.logicalKey == LogicalKeyboardKey.f2) {
            if (_selectedPath != null && _editingPath == null) {
              _startEditing(_selectedPath!, _selectedPath!.split('/').last);
            }
          } else if (event.logicalKey == LogicalKeyboardKey.delete) {
            if (_selectedPath != null && _editingPath == null) {
              bool isFolder = Directory(_selectedPath!).existsSync();
              widget.onDeleted(_selectedPath!, isFolder);
            }
          } else if (isControlPressed &&
              event.logicalKey == LogicalKeyboardKey.keyC) {
            if (_selectedPath != null && _editingPath == null) {
              widget.onCopy(_selectedPath!);
            }
          } else if (isControlPressed &&
              event.logicalKey == LogicalKeyboardKey.keyV) {
            if (_editingPath == null) {
              String target = _selectedPath ?? widget.folderPath ?? '';
              if (target.isNotEmpty) {
                if (File(target).existsSync()) {
                  target = File(target).parent.path;
                }
                widget.onPaste(target);
              }
            }
          }
        }
      },
      child: GestureDetector(
        onTap: () => _sidebarFocusNode.requestFocus(),
        onSecondaryTapDown: (details) {
          _showContextMenu(
            context,
            details.globalPosition,
            widget.folderPath,
            true,
          );
        },
        child: Container(
          width: widget.width,
          color: AppTheme.sidebarBackground,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DragTarget<String>(
                onWillAcceptWithDetails: (details) =>
                    widget.folderPath != null &&
                    details.data != widget.folderPath &&
                    !widget.folderPath!.startsWith('${details.data}/'),
                onAcceptWithDetails: (details) =>
                    widget.onMove(details.data, widget.folderPath!),
                builder: (context, candidateData, rejectedData) {
                  final isOver = candidateData.isNotEmpty;
                  return Container(
                    color: isOver
                        ? AppTheme.accent.withValues(alpha: 0.2)
                        : Colors.transparent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12.0,
                      vertical: 8.0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            widget.folderName ?? 'Explorer',
                            style: TextStyle(
                              color: isOver
                                  ? AppTheme.accent
                                  : AppTheme.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.create_new_folder_outlined,
                            size: 18,
                          ),
                          onPressed: () =>
                              widget.onFolderCreated(_selectedPath),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Nova Pasta',
                          color: AppTheme.textSecondary,
                        ),
                        if (widget.onRefresh != null) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(
                              Icons.refresh,
                              size: 18,
                            ),
                            onPressed: widget.onRefresh,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Atualizar',
                            color: AppTheme.textSecondary,
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    // Untitled / Open files not in the tree
                    ...widget.openTabs
                        .where(
                          (tab) =>
                              tab.startsWith('Untitled') ||
                              tab.startsWith('Nova Nota'),
                        )
                        .map((tab) => _buildFileItem(tab, path: tab)),
                    if (widget.openTabs.any(
                      (tab) =>
                          tab.startsWith('Untitled') ||
                          tab.startsWith('Nova Nota'),
                    ))
                      const Divider(height: 1, indent: 16, endIndent: 16),

                    if (widget.folderName != null) ...[
                      _buildFolderItem(
                        widget.folderName!,
                        path: widget.folderPath,
                      ),
                      if (_expandedFolders.contains(
                        widget.folderPath ?? widget.folderName,
                      ))
                        ..._buildTreeNodes(
                          _subFolderCache[widget.folderPath] ??
                              widget.folderFiles,
                          indent: 1,
                        ),
                    ] else ...[
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: Text(
                            'Nenhuma pasta aberta',
                            style: TextStyle(
                              color: AppTheme.textSecondary.withValues(
                                alpha: 0.5,
                              ),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTreeNodes(
    List<Map<String, dynamic>> items, {
    int indent = 0,
  }) {
    List<Widget> nodes = [];
    for (var item in items) {
      if (item['isFolder']) {
        nodes.add(
          _buildFolderItem(item['name'], indent: indent, path: item['path']),
        );
        if (_expandedFolders.contains(item['path'])) {
          nodes.addAll(
            _buildTreeNodes(
              _subFolderCache[item['path']] ?? [],
              indent: indent + 1,
            ),
          );
        }
      } else {
        nodes.add(
          _buildFileItem(item['name'], path: item['path'], indent: indent),
        );
      }
    }
    return nodes;
  }

  Widget _buildFolderItem(String label, {int indent = 0, String? path}) {
    final folderKey = path ?? label;
    bool isExpanded = _expandedFolders.contains(folderKey);
    return InkWell(
      onTap: () {
        final folderKey = path ?? label;
        setState(() {
          _selectedPath = folderKey;
          if (isExpanded) {
            _expandedFolders.remove(folderKey);
          } else {
            _expandedFolders.add(folderKey);
            if (path != null) {
              _loadSubFolder(path, label);
            }
          }
        });
        widget.onFolderSelected(path);
      },
      onSecondaryTapDown: (details) {
        if (path != null) {
          setState(() => _selectedPath = path);
          _showContextMenu(context, details.globalPosition, path, true);
        }
      },
        child: DragTarget<String>(
          onWillAcceptWithDetails: (details) =>
              details.data != folderKey && !folderKey.startsWith('${details.data}/'),
          onAcceptWithDetails: (details) => widget.onMove(details.data, folderKey),
          builder: (context, candidateData, rejectedData) {
            final isOver = candidateData.isNotEmpty;
            return Draggable<String>(
              data: folderKey,
              feedback: Material(
                color: Colors.transparent,
                child: Opacity(
                  opacity: 0.8,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 4,
                        )
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.folder, size: 16, color: Colors.blueAccent),
                        const SizedBox(width: 8),
                        Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.3,
                child: _buildTreeItem(
                  Icons.folder,
                  label,
                  isExpanded,
                  isFolder: true,
                  indent: indent,
                  isSelected: _selectedPath == folderKey,
                  path: path,
                ),
              ),
              child: _buildTreeItem(
                Icons.folder,
                label,
                isExpanded,
                isFolder: true,
                indent: indent,
                isSelected: _selectedPath == folderKey,
                path: path,
                isHighlighted: isOver,
              ),
            );
          },
        ),
      );
  }

  Widget _buildFileItem(String label, {required String path, int indent = 0}) {
    return InkWell(
      onTap: () {
        setState(() => _selectedPath = path);
        widget.onFileSelected(path);
        widget.onFolderSelected(File(path).parent.path);
      },
      onSecondaryTapDown: (details) {
        setState(() => _selectedPath = path);
        _showContextMenu(context, details.globalPosition, path, false);
      },
        child: Draggable<String>(
          data: path,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.8,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 4,
                    )
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.insert_drive_file, size: 16, color: AppTheme.textSecondary),
                    const SizedBox(width: 8),
                    Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: _buildTreeItem(
              Icons.insert_drive_file,
              label,
              false,
              indent: indent,
              isSelected: _selectedPath == path,
              path: path,
            ),
          ),
          child: _buildTreeItem(
            Icons.insert_drive_file,
            label,
            false,
            indent: indent,
            isSelected: _selectedPath == path,
            path: path,
          ),
        ),
      );
  }

  Widget _buildTreeItem(
    IconData icon,
    String label,
    bool isExpanded, {
    int indent = 0,
    bool isSelected = false,
    bool isFolder = false,
    String? path,
    bool isHighlighted = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isHighlighted
            ? AppTheme.accent.withValues(alpha: 0.2)
            : (isSelected
                ? AppTheme.accent.withValues(alpha: 0.15)
                : Colors.transparent),
        border: isHighlighted
            ? Border.all(color: AppTheme.accent, width: 1.5)
            : null,
      ),
      padding: EdgeInsets.only(
        left: 12.0 + (indent * 16.0),
        top: 6.0,
        bottom: 6.0,
        right: 12.0,
      ),
      child: Row(
        children: [
          if (isFolder)
            Icon(
              isExpanded ? Icons.arrow_drop_down : Icons.arrow_right,
              size: 16,
              color: AppTheme.textSecondary,
            )
          else
            const SizedBox(width: 16),
          const SizedBox(width: 4),
          Icon(
            icon,
            size: 16,
            color: isFolder ? Colors.blueAccent : AppTheme.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _editingPath == (path ?? label)
                ? TextField(
                    controller: _renameController,
                    focusNode: _renameFocusNode,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _submitRename(),
                    onTapOutside: (_) => _submitRename(),
                  )
                : Text(
                    label,
                    style: TextStyle(
                      color: isSelected
                          ? AppTheme.accent
                          : AppTheme.textPrimary,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
          ),
        ],
      ),
    );
  }
}
