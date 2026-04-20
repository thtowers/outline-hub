import 'package:flutter/material.dart';
import 'screens/main_window.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const FlutterCodeApp());
}

class FlutterCodeApp extends StatelessWidget {
  const FlutterCodeApp({Key? key}) : super(key: key);

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
