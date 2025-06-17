import 'package:flutter/material.dart';
import 'routes.dart';
import 'screens/login_screen.dart';
import 'package:flutter/foundation.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'GEW ERP 1.1',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.orange,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Colors.orange[50],
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFE0B2), // optional override
          foregroundColor: Colors.black,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFE0B2),
            foregroundColor: Colors.black,
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFFFFA726),
          foregroundColor: Colors.black,
        ),
      ),
      routerConfig: router,
    );
  }

  /*return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Test Report App',
      theme: ThemeData(primarySwatch: Colors.blue),
      routerConfig: router,
    );*/
}
