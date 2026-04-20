import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SideBar extends StatefulWidget {
  final String selectedFile;
  final Function(String) onFileSelected;

  const SideBar({
    Key? key,
    required this.selectedFile,
    required this.onFileSelected,
  }) : super(key: key);

  @override
  State<SideBar> createState() => _SideBarState();
}

class _SideBarState extends State<SideBar> {
  final Set<String> _expandedFolders = {'src', 'lib'};

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      color: AppTheme.sidebarBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Text(
              'MY_PROJECT',
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
                _buildFolderItem('lib'),
                if (_expandedFolders.contains('lib'))
                  _buildFileItem('main.dart', indent: 1),
                _buildFolderItem('src'),
                if (_expandedFolders.contains('src')) ...[
                  _buildFileItem('app.dart', indent: 1),
                  _buildFileItem('main.dart', indent: 1),
                ],
                _buildFolderItem('plugins'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderItem(String label) {
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
      child: _buildTreeItem(Icons.folder, label, isExpanded, isFolder: true),
    );
  }

  Widget _buildFileItem(String label, {int indent = 0}) {
    return InkWell(
      onTap: () {
        widget.onFileSelected(label);
      },
      child: _buildTreeItem(Icons.insert_drive_file, label, false, indent: indent, isSelected: widget.selectedFile == label),
    );
  }

  Widget _buildTreeItem(IconData icon, String label, bool isExpanded, {int indent = 0, bool isSelected = false, bool isFolder = false}) {
    return Container(
      color: isSelected ? AppTheme.accent.withOpacity(0.15) : Colors.transparent,
      padding: EdgeInsets.only(
        left: 12.0 + (indent * 16.0),
        top: 6.0,
        bottom: 6.0,
        right: 12.0,
      ),
      child: Row(
        children: [
          if (isFolder)
            Icon(isExpanded ? Icons.arrow_drop_down : Icons.arrow_right, size: 16, color: AppTheme.textSecondary)
          else
            const SizedBox(width: 16),
          const SizedBox(width: 4),
          Icon(icon, size: 16, color: isFolder ? Colors.blueAccent : AppTheme.textSecondary),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? AppTheme.accent : AppTheme.textPrimary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
