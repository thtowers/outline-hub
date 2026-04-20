import 'package:flutter/material.dart';
import '../widgets/header_bar.dart';
import '../widgets/side_bar.dart';
import '../widgets/document_view.dart';
import '../theme/app_theme.dart';

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

  void _openFile(String filename) {
    setState(() {
      final newTabs = List<String>.from(_openTabs);
      if (!newTabs.contains(filename)) {
        newTabs.add(filename);
        _activeTabIndex = newTabs.length - 1;
      } else {
        _activeTabIndex = newTabs.indexOf(filename);
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
                  onFileSelected: _openFile,
                ),
                const VerticalDivider(width: 1),
                // Center Document View
                Expanded(
                  child: DocumentView(
                    tabs: _openTabs,
                    activeTabIndex: _activeTabIndex,
                    onCloseTab: _closeTab,
                    onSelectTab: _selectTab,
                    onReorderTab: _reorderTab,
                    onNewTab: _handleNewTab,
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
