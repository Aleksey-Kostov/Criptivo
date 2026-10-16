import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/auth/auth_service.dart';
import 'core/crypto/key_manager.dart';
import 'core/supabase_config.dart';
import 'core/theme/criptivo_theme.dart';
import 'features/auth/login_page.dart';
import 'features/home/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  // Генерира ключове само ако липсват локално
  await KeyManager.ensureKeys();

  runApp(const CriptivoApp());
}

class CriptivoApp extends StatelessWidget {
  const CriptivoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Criptivo',
      debugShowCheckedModeBanner: false,
      theme: CriptivoTheme.dark,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _synced = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;

        if (session != null) {
          // Синхронизираме public key само веднъж след login
          if (!_synced) {
            _synced = true;
            unawaited(AuthService.syncPublicKeyToProfile());
          }
          return const HomePage();
        }

        // При logout нулираме флага
        _synced = false;
        return const LoginPage();
      },
    );
  }
}
