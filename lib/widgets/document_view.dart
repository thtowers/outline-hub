import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class DocumentView extends StatefulWidget {
  final List<String> tabs;
  final int activeTabIndex;
  final Function(int) onCloseTab;
  final Function(int) onSelectTab;
  final void Function(int, int) onReorderTab;
  final VoidCallback onNewTab;

  const DocumentView({
    super.key,
    required this.tabs,
    required this.activeTabIndex,
    required this.onCloseTab,
    required this.onSelectTab,
    required this.onReorderTab,
    required this.onNewTab,
  });

  @override
  State<DocumentView> createState() => _DocumentViewState();
}

class _DocumentViewState extends State<DocumentView> {
  late TextEditingController _controller;

  final Map<String, String> _fileContents = {
    'main.dart': '''import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Editor',
      theme: ThemeData(
        brightness: Brightness.dark,
      ),
      home: const Scaffold(
        body: Center(
          child: Text('Hello World!'),
        ),
      ),
    );
  }
}''',
    'app.dart': '''import 'package:flutter/material.dart';

class AppTheme {
  static const Color background = Color(0xFF1E1E1E);
  static const Color surface = Color(0xFF282828);
  static const Color accent = Colors.blueAccent;
  
  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    primaryColor: surface,
  );
}''',
  };

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _getContentForCurrentTab());
  }

  String _getContentForCurrentTab() {
    if (widget.tabs.isEmpty) return '';
    String file = widget.tabs[widget.activeTabIndex];
    return _fileContents[file] ?? '// $file\n';
  }

  @override
  void didUpdateWidget(DocumentView oldWidget) {
    super.didUpdateWidget(oldWidget);

    String? oldActiveFile;
    if (oldWidget.tabs.isNotEmpty &&
        oldWidget.activeTabIndex < oldWidget.tabs.length) {
      oldActiveFile = oldWidget.tabs[oldWidget.activeTabIndex];
    }

    String? newActiveFile;
    if (widget.tabs.isNotEmpty && widget.activeTabIndex < widget.tabs.length) {
      newActiveFile = widget.tabs[widget.activeTabIndex];
    }

    if (oldActiveFile != newActiveFile) {
      if (oldActiveFile != null) {
        _fileContents[oldActiveFile] = _controller.text;
      }
      if (newActiveFile != null) {
        if (!_fileContents.containsKey(newActiveFile)) {
          _fileContents[newActiveFile] = '// $newActiveFile\n';
        }
        _controller.text = _fileContents[newActiveFile]!;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
                        ElevatedButton.icon(
                          onPressed: widget.onNewTab,
                          icon: const Icon(Icons.add),
                          label: const Text('Create New File'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accent.withOpacity(0.1),
                            foregroundColor: AppTheme.accent,
                            elevation: 0,
                          ),
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
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8.0, top: 8.0),
                          child: TextField(
                            controller: _controller,
                            onChanged: (text) {
                              if (widget.tabs.isNotEmpty &&
                                  widget.activeTabIndex < widget.tabs.length) {
                                String currentFile =
                                    widget.tabs[widget.activeTabIndex];
                                _fileContents[currentFile] = text;
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
                  return ReorderableDragStartListener(
                    key: ValueKey(widget.tabs[index]),
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
                              Icons.insert_drive_file,
                              size: 14,
                              color: isSelected
                                  ? AppTheme.textPrimary
                                  : AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              widget.tabs[index],
                              style: TextStyle(
                                color: isSelected
                                    ? AppTheme.textPrimary
                                    : AppTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 12),
                            InkWell(
                              borderRadius: BorderRadius.circular(2),
                              onTap: () {
                                widget.onCloseTab(index);
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(2.0),
                                child: Icon(
                                  Icons.close,
                                  size: 14,
                                  color: isSelected
                                      ? AppTheme.textPrimary
                                      : AppTheme.textSecondary,
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
          // Plus button at the end of tabs
          Material(
            color: Colors.transparent,
            child: IconButton(
              icon: const Icon(Icons.add, size: 18),
              onPressed: widget.onNewTab,
              tooltip: 'New Tab',
              splashRadius: 18,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineNumbers() {
    return Container(
      width: 40,
      padding: const EdgeInsets.only(top: 8.0, right: 8.0),
      color: AppTheme.sidebarBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(
          20,
          (index) => Text(
            '\${index + 1}',
            style: AppTheme.codeTextStyle.copyWith(
              color: AppTheme.textSecondary.withOpacity(0.5),
            ),
          ),
        ),
      ),
    );
  }
}
