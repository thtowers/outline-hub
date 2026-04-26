import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/main_window.dart';
import 'controllers/theme_controller.dart';
import 'theme/app_theme.dart';

//ALTERAR AQUI O NOME DO APLICATIVO
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa o FFI
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Adiciona esta linha.
  await windowManager.ensureInitialized();

  // Configura as opções da janela.
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 720),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    minimumSize: Size(900, 600),
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final themeController = ThemeController();
  AppTheme.init(themeController);
  runApp(FlutterCodeApp(themeController: themeController));
}

class FlutterCodeApp extends StatelessWidget {
  final ThemeController themeController;
  const FlutterCodeApp({super.key, required this.themeController});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        return MaterialApp(
          title: 'Outline Hub',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeController.themeMode,
          localizationsDelegates: const [
            AppFlowyEditorLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          home: MainWindow(themeController: themeController),
        );
      },
    );
  }
}
