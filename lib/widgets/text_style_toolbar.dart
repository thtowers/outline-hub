import 'package:flutter/material.dart';
import '../controllers/text_style_controller.dart';
import '../theme/app_theme.dart';

class TextStyleToolbar extends StatelessWidget {
  final TextStyleController controller;

  const TextStyleToolbar({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildActionButton(
                icon: Icons.remove,
                onPressed: () {
                  debugPrint('TextStyleToolbar: Clicked -');
                  controller.decrementSize();
                },
                tooltip: 'Diminuir Texto',
              ),
              Container(
                width: 30,
                alignment: Alignment.center,
                child: Text(
                  "${controller.fontSize.toInt()}",
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _buildActionButton(
                icon: Icons.add,
                onPressed: () {
                  debugPrint('TextStyleToolbar: Clicked +');
                  controller.incrementSize();
                },
                tooltip: 'Aumentar Texto',
              ),
              const SizedBox(width: 4),
              _buildToggleButton(
                label: 'B',
                isSelected: controller.isBold,
                onPressed: () {
                  debugPrint('TextStyleToolbar: Clicked B');
                  controller.toggleBold();
                },
                tooltip: 'Negrito',
                isBold: true,
              ),
              const SizedBox(width: 2),
              _buildToggleButton(
                label: 'I',
                isSelected: controller.isItalic,
                onPressed: () {
                  debugPrint('TextStyleToolbar: Clicked I');
                  controller.toggleItalic();
                },
                tooltip: 'Itálico',
                isItalic: true,
              ),
              const SizedBox(width: 4),
              _buildActionButton(
                icon: Icons.horizontal_rule,
                onPressed: () {
                  debugPrint('TextStyleToolbar: Clicked Divider');
                  controller.insertDivider();
                },
                tooltip: 'Inserir Linha Separadora',
              ),
              const SizedBox(width: 4),
              _buildActionButton(
                icon: Icons.edit_note_rounded,
                onPressed: () {
                  debugPrint('TextStyleToolbar: Clicked Note');
                  controller.toggleNote();
                },
                tooltip: 'Adicionar Nota/Destaque',
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        icon: Icon(icon, size: 16),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        splashRadius: 16,
        color: AppTheme.textSecondary,
        tooltip: tooltip,
      ),
    );
  }

  Widget _buildToggleButton({
    required String label,
    required bool isSelected,
    required VoidCallback onPressed,
    required String tooltip,
    bool isBold = false,
    bool isItalic = false,
  }) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.accent.withValues(alpha: 0.2) : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? AppTheme.accent : AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                  fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
