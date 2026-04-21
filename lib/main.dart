import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'screens/main_window.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Must add this line.
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 720),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    minimumSize: Size(800, 600),
  );
  
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const FlutterCodeApp());
}

class FlutterCodeApp extends StatelessWidget {
  const FlutterCodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Code',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainWindow(),
    );
  }
}
