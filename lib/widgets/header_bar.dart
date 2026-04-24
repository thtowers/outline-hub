import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/edit_format.dart';
import '../controllers/text_style_controller.dart';
import 'text_style_toolbar.dart';

class HeaderBar extends StatelessWidget {
  final VoidCallback? onSearchToggle;
  final VoidCallback? onTerminalToggle;
  final VoidCallback? onNewTab;
  final VoidCallback? onSave;
  final VoidCallback? onOpenFolder;
  final VoidCallback? onOpenFile;

  // Tab settings
  final int tabWidth;
  final bool autoIndent;
  final bool insertSpaces;
  final EditFormat currentFormat;
  final ValueChanged<int> onTabWidthChanged;
  final ValueChanged<bool> onAutoIndentChanged;
  final ValueChanged<bool> onInsertSpacesChanged;
  final ValueChanged<EditFormat> onFormatChanged;
  final TextStyleController textStyleController;
  final VoidCallback? onZenModeToggle;
  final VoidCallback? onSettingsToggle;
  final VoidCallback? onSpeechToggle;

  const HeaderBar({
    super.key,
    this.onSearchToggle,
    this.onTerminalToggle,
    this.onNewTab,
    this.onSave,
    this.onOpenFolder,
    this.onOpenFile,
    required this.tabWidth,
    required this.autoIndent,
    required this.insertSpaces,
    required this.currentFormat,
    required this.onTabWidthChanged,
    required this.onAutoIndentChanged,
    required this.onInsertSpacesChanged,
    required this.onFormatChanged,
    required this.textStyleController,
    this.onZenModeToggle,
    this.onSettingsToggle,
    this.onSpeechToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: AppTheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Left actions
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.folder_open_outlined, size: 20),
                  onPressed: onOpenFolder ?? () {},
                  splashRadius: 20,
                  tooltip: 'Abrir Pasta',
                ),
                IconButton(
                  icon: const Icon(Icons.file_open_outlined, size: 20),
                  onPressed: onOpenFile ?? () {},
                  splashRadius: 20,
                  tooltip: 'Abrir Arquivo',
                ),
                IconButton(
                  icon: const Icon(Icons.save_outlined, size: 20),
                  onPressed: onSave ?? () {},
                  splashRadius: 20,
                  tooltip: 'Salvar Arquivo (Ctrl+S)',
                ),
              ],
            ),

            Flexible(
              child: Container(
                height: 32,
                constraints: const BoxConstraints(maxWidth: 800),
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: AppTheme.textSecondary.withValues(alpha: 0.2),
                  ),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTabSettingButton(context),
                      const VerticalDivider(width: 1),
                      _buildFormatSettingButton(context),
                      const VerticalDivider(width: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: TextStyleToolbar(controller: textStyleController),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Right actions
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.timer_outlined, size: 20),
                  onPressed: onSpeechToggle ?? () {},
                  splashRadius: 20,
                  tooltip: 'Planejador de Palestra',
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 20),
                  onPressed: onSettingsToggle ?? () {},
                  splashRadius: 20,
                  tooltip: 'Configurações do Editor',
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.open_in_full, size: 18),
                  onPressed: onZenModeToggle ?? () {},
                  splashRadius: 20,
                  tooltip: 'Alternar Tela Cheia',
                ),
                const SizedBox(width: 4),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabSettingButton(BuildContext context) {
    return Tooltip(
      message: 'Configurações de Tabulação e Indentação',
      child: InkWell(
        onTap: () => _showTabSettings(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Icon(Icons.keyboard_tab, size: 16),
              const SizedBox(width: 8),
              Text(
                '$tabWidth Espaços',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormatSettingButton(BuildContext context) {
    return Tooltip(
      message: 'Alterar Formato do Documento (Markdown/Texto)',
      child: InkWell(
        onTap: () => _showFormatSettings(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Icon(Icons.code, size: 16),
              const SizedBox(width: 8),
              Text(
                currentFormat.label,
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFormatSettings(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) {
        return Stack(
          children: [
            Positioned(
              top: 52,
              left: MediaQuery.of(context).size.width / 2 - 80,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                color: AppTheme.surface,
                child: Container(
                  width: 200,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: EditFormat.values.map((format) {
                      final isSelected = format == currentFormat;
                      return InkWell(
                        onTap: () {
                          onFormatChanged(format);
                          Navigator.pop(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          color: isSelected
                              ? AppTheme.accent.withValues(alpha: 0.1)
                              : null,
                          child: Row(
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.check_circle
                                    : _getFormatIcon(format),
                                size: 16,
                                color: isSelected
                                    ? AppTheme.accent
                                    : AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                format.label,
                                style: TextStyle(
                                  color: isSelected
                                      ? AppTheme.accent
                                      : AppTheme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
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

  void _showTabSettings(BuildContext context) {
    // Capture local state for the dialog to ensure immediate UI updates
    int localTabWidth = tabWidth;
    bool localAutoIndent = autoIndent;
    bool localInsertSpaces = insertSpaces;

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Stack(
              children: [
                Positioned(
                  top: 52,
                  left: MediaQuery.of(context).size.width / 2 - 160,
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(8),
                    color: AppTheme.surface,
                    child: Container(
                      width: 320,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildSwitchRow(
                            'Indentação automática',
                            localAutoIndent,
                            (val) {
                              onAutoIndentChanged(val);
                              setDialogState(() => localAutoIndent = val);
                            },
                          ),
                          const SizedBox(height: 12),
                          _buildSwitchRow(
                            'Inserir espaços em vez de tabulações',
                            localInsertSpaces,
                            (val) {
                              onInsertSpacesChanged(val);
                              setDialogState(() => localInsertSpaces = val);
                            },
                          ),
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Largura da tabulação',
                                style: TextStyle(color: AppTheme.textPrimary),
                              ),
                              Row(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: AppTheme.textSecondary
                                            .withValues(alpha: 0.3),
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                          child: Text(
                                            '$localTabWidth',
                                            style: TextStyle(
                                              color: AppTheme.textPrimary,
                                            ),
                                          ),
                                        ),
                                        const VerticalDivider(width: 1),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.remove,
                                            size: 14,
                                          ),
                                          onPressed: () {
                                            int newVal = localTabWidth > 1
                                                ? localTabWidth - 1
                                                : 1;
                                            onTabWidthChanged(newVal);
                                            setDialogState(
                                              () => localTabWidth = newVal,
                                            );
                                          },
                                          constraints: const BoxConstraints(
                                            maxWidth: 32,
                                            maxHeight: 32,
                                          ),
                                          padding: EdgeInsets.zero,
                                        ),
                                        const VerticalDivider(width: 1),
                                        IconButton(
                                          icon: const Icon(Icons.add, size: 14),
                                          onPressed: () {
                                            int newVal = localTabWidth + 1;
                                            onTabWidthChanged(newVal);
                                            setDialogState(
                                              () => localTabWidth = newVal,
                                            );
                                          },
                                          constraints: const BoxConstraints(
                                            maxWidth: 32,
                                            maxHeight: 32,
                                          ),
                                          padding: EdgeInsets.zero,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSwitchRow(
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppTheme.accent,
        ),
      ],
    );
  }
}
