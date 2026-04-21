import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'dart:io';

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
  });

  @override
  State<DocumentView> createState() => _DocumentViewState();
}

class _DocumentViewState extends State<DocumentView> {
  late TextEditingController _controller;
  late ScrollController _editorScrollController;
  late ScrollController _lineNumbersScrollController;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _getContentForCurrentTab());
    _editorScrollController = ScrollController();
    _lineNumbersScrollController = ScrollController();

    // Sync line numbers scroll with editor scroll
    _editorScrollController.addListener(() {
      if (_lineNumbersScrollController.hasClients) {
        _lineNumbersScrollController
            .jumpTo(_editorScrollController.offset);
      }
    });

    // Rebuild UI on text changes to update line count
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  String _getContentForCurrentTab() {
    if (widget.tabs.isEmpty) return '';
    String path = widget.tabs[widget.activeTabIndex];
    
    // 1. Check if it's already in memory
    if (widget.fileContents.containsKey(path)) return widget.fileContents[path]!;

    // 2. Try to read from real disk
    try {
      final file = File(path);
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        debugPrint('Successfully read file: $path');
        return content;
      } else {
        debugPrint('FILE NOT FOUND AT: "$path"');
        return '// Error: File not found at:\n// $path\n';
      }
    } catch (e) {
      debugPrint('ERROR READING FILE: $e');
      return '// Error reading file:\n// $e\n';
    }
  }

  @override
  void didUpdateWidget(DocumentView oldWidget) {
    super.didUpdateWidget(oldWidget);

    String? oldActivePath = oldWidget.tabs.isNotEmpty && oldWidget.activeTabIndex < oldWidget.tabs.length
        ? oldWidget.tabs[oldWidget.activeTabIndex] : null;
    String? newActivePath = widget.tabs.isNotEmpty && widget.activeTabIndex < widget.tabs.length
        ? widget.tabs[widget.activeTabIndex] : null;

    if (oldActivePath != newActivePath || oldWidget.tabs.length != widget.tabs.length) {
      _controller.text = _getContentForCurrentTab();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _editorScrollController.dispose();
    _lineNumbersScrollController.dispose();
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
    return Icons.insert_drive_file;
  }

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
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.edit_note,
                          size: 64,
                          color: AppTheme.textSecondary.withOpacity(0.2),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No open files',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            ElevatedButton.icon(
                              onPressed: widget.onNewTab,
                              icon: const Icon(Icons.add),
                              label: const Text('New File'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    AppTheme.accent.withOpacity(0.1),
                                foregroundColor: AppTheme.accent,
                                elevation: 0,
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: widget.onOpenFile,
                              icon: const Icon(Icons.file_open),
                              label: const Text('Open File'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    AppTheme.accent.withOpacity(0.1),
                                foregroundColor: AppTheme.accent,
                                elevation: 0,
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: widget.onOpenFolder,
                              icon: const Icon(Icons.folder_open),
                              label: const Text('Open Folder'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    AppTheme.accent.withOpacity(0.1),
                                foregroundColor: AppTheme.accent,
                                elevation: 0,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLineNumbers(),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: 2000,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8.0, top: 8.0),
                              child: TextField(
                                controller: _controller,
                                scrollController: _editorScrollController,
                                onChanged: (text) {
                                  if (widget.tabs.isNotEmpty &&
                                      widget.activeTabIndex <
                                          widget.tabs.length) {
                                    String currentPath =
                                        widget.tabs[widget.activeTabIndex];
                                    widget.onContentChanged(currentPath, text);
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
                                scrollPadding: const EdgeInsets.only(bottom: 80),
                                textAlignVertical: TextAlignVertical.top,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
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
                      onTap: () {
                        widget.onSelectTab(index);
                      },
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
                            Text(
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
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () => widget.onCloseTab(index),
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: AppTheme.textSecondary,
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
          // Tool buttons: Save and New
          Material(
            color: Colors.transparent,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: widget.onNewTab,
                  tooltip: 'New Tab',
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineNumbers() {
    final text = _controller.text;
    final lineCount = text.isEmpty ? 1 : '\n'.allMatches(text).length + 1;
    const double lineHeight = 21.0;

    return Container(
      width: 48,
      color: AppTheme.sidebarBackground,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView.builder(
          controller: _lineNumbersScrollController,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 8.0, bottom: 100.0),
          itemCount: lineCount,
          itemExtent: lineHeight,
          itemBuilder: (context, index) {
            return Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 8.0),
              child: Text(
                '${index + 1}',
                style: AppTheme.codeTextStyle.copyWith(
                  color: AppTheme.textSecondary.withOpacity(0.4),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
