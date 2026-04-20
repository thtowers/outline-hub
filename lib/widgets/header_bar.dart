import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class HeaderBar extends StatelessWidget {
  final VoidCallback? onSearchToggle;
  final VoidCallback? onTerminalToggle;
  final VoidCallback? onNewTab;

  const HeaderBar({
    super.key,
    this.onSearchToggle,
    this.onTerminalToggle,
    this.onNewTab,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: AppTheme.surface,
      child: Row(
        children: [
          // Window controls (mocked)
          const SizedBox(width: 16),
          const Icon(Icons.menu, size: 18),
          const SizedBox(width: 24),

          // Action Buttons
          IconButton(
            icon: const Icon(Icons.note_add_outlined),
            tooltip: 'New Tab',
            onPressed: onNewTab ?? () {},
            splashRadius: 20,
          ),
          IconButton(
            icon: const Icon(Icons.save_outlined),
            tooltip: 'Save',
            onPressed: () {},
            splashRadius: 20,
          ),

          const Spacer(),

          // Title
          Text(
            'main.dart - Editor',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),

          const Spacer(),

          // Right panel options
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Find',
            onPressed: onSearchToggle ?? () {},
            splashRadius: 20,
          ),
          IconButton(
            icon: const Icon(Icons.terminal),
            tooltip: 'Terminal',
            onPressed: onTerminalToggle ?? () {},
            splashRadius: 20,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
