import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const RN04App());
}

class RN04App extends StatelessWidget {
  const RN04App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RN04 Launcher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF8B6914),
          secondary: Color(0xFFF0E68C),
          surface: Color(0xFF1A1A1A),
        ),
        drawerTheme: const DrawerThemeData(
          backgroundColor: Color(0xFF1A1A1A),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Color(0xFFE0D5A0)),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
