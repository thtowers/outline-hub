import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class DurationPickerDialog extends StatefulWidget {
  final Duration initialDuration;
  final String title;

  const DurationPickerDialog({
    super.key,
    required this.initialDuration,
    required this.title,
  });

  @override
  State<DurationPickerDialog> createState() => _DurationPickerDialogState();

  static Future<Duration?> show(
    BuildContext context, {
    required Duration initialDuration,
    required String title,
  }) {
    return showDialog<Duration>(
      context: context,
      builder: (context) => DurationPickerDialog(
        initialDuration: initialDuration,
        title: title,
      ),
    );
  }
}

class _DurationPickerDialogState extends State<DurationPickerDialog> {
  late Duration _selectedDuration;

  @override
  void initState() {
    super.initState();
    _selectedDuration = widget.initialDuration;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: AppTheme.uiStyle.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: AppTheme.uiStyle.copyWith(
                      color: AppTheme.textPrimary,
                      fontSize: 22,
                    ),
                  ),
                ),
                child: CupertinoTimerPicker(
                  mode: CupertinoTimerPickerMode.ms,
                  initialTimerDuration: _selectedDuration,
                  onTimerDurationChanged: (duration) {
                    setState(() {
                      _selectedDuration = duration;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'CANCELAR',
                    style: AppTheme.uiStyle.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(_selectedDuration),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'DEFINIR',
                    style: AppTheme.uiStyle.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
