import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/crypto/key_manager.dart';
import 'core/supabase_config.dart';
import 'core/theme/chat_background_style.dart';
import 'core/theme/criptivo_theme.dart';
import 'features/auth/login_page.dart';
import 'features/home/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );

  // Генерира ключове само ако липсват локално.
  await KeyManager.ensureKeys();

  // Зарежда избрания фон за чата.
  await ChatBackgroundStyle.load();

  runApp(const CriptivoApp());
}

class CriptivoApp extends StatelessWidget {
  const CriptivoApp({super.key, this.home});

  /// Позволява на тестовете да подадат собствен начален екран,
  /// без да е необходимо да се инициализира Supabase.
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Criptivo',
      debugShowCheckedModeBanner: false,
      theme: CriptivoTheme.dark,
      home: home ?? const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;

        if (session != null) {
          return const HomePage();
        }

        return const LoginPage();
      },
    );
  }
}
