import 'package:flutter/material.dart';
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

  const SideBar({
    super.key,
    required this.selectedFile,
    required this.openTabs,
    required this.folderFiles,
    this.folderName,
    this.folderPath,
    required this.width,
    required this.onFileSelected,
  });

  @override
  State<SideBar> createState() => _SideBarState();
}

class _SideBarState extends State<SideBar> {
  final Set<String> _expandedFolders = {'src', 'lib'};

  void _showContextMenu(BuildContext context, Offset globalPosition, String path, bool isFolder) async {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    
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
              Text('Open in folder', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
            ],
          ),
        ),
      ],
    );

    if (action == 'open_location') {
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      color: AppTheme.sidebarBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Text(
              widget.folderName ?? 'NO FOLDER OPEN',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // Untitled / Open files not in the tree
                ...widget.openTabs
                    .where((tab) => tab.startsWith('Untitled'))
                    .map((tab) => _buildFileItem(tab, path: tab)),
                if (widget.openTabs.any((tab) => tab.startsWith('Untitled')))
                  const Divider(height: 1, indent: 16, endIndent: 16),

                if (widget.folderName != null) ...[
                  _buildFolderItem(widget.folderName!, path: widget.folderPath),
                  if (_expandedFolders.contains(widget.folderName))
                    ..._buildTreeNodes(widget.folderFiles, indent: 1),
                ] else ...[
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Text(
                        'No folder open',
                        style: TextStyle(
                          color: AppTheme.textSecondary.withValues(alpha: 0.5),
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
    );
  }

  List<Widget> _buildTreeNodes(List<Map<String, dynamic>> items,
      {int indent = 0}) {
    List<Widget> nodes = [];
    for (var item in items) {
      if (item['isFolder']) {
        nodes.add(_buildFolderItem(item['name'], indent: indent, path: item['path']));
        if (_expandedFolders.contains(item['name'])) {
          nodes.addAll(_buildTreeNodes(
            List<Map<String, dynamic>>.from(item['children'] ?? []),
            indent: indent + 1,
          ));
        }
      } else {
        nodes.add(_buildFileItem(item['name'],
            path: item['path'], indent: indent));
      }
    }
    return nodes;
  }

  Widget _buildFolderItem(String label, {int indent = 0, String? path}) {
    bool isExpanded = _expandedFolders.contains(label);
    return InkWell(
      onTap: () {
        setState(() {
          if (isExpanded) {
            _expandedFolders.remove(label);
          } else {
            _expandedFolders.add(label);
          }
        });
      },
      onSecondaryTapDown: (details) {
        if (path != null) {
          _showContextMenu(context, details.globalPosition, path, true);
        }
      },
      child: _buildTreeItem(Icons.folder, label, isExpanded,
          isFolder: true, indent: indent),
    );
  }

  Widget _buildFileItem(String label, {required String path, int indent = 0}) {
    return InkWell(
      onTap: () {
        widget.onFileSelected(path);
      },
      onSecondaryTapDown: (details) {
        _showContextMenu(context, details.globalPosition, path, false);
      },
      child: _buildTreeItem(
        Icons.insert_drive_file,
        label,
        false,
        indent: indent,
        isSelected: widget.selectedFile == path,
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
  }) {
    return Container(
      color: isSelected
          ? AppTheme.accent.withValues(alpha: 0.15)
          : Colors.transparent,
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
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? AppTheme.accent : AppTheme.textPrimary,
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
