import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/supabase_config.dart';
import 'core/theme/chat_background_style.dart';
import 'core/theme/criptivo_theme.dart';
import 'features/auth/login_page.dart';
import 'features/home/home_page.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await RustLib.init();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );

  // ВАЖНО:
  // Не генерираме криптографични ключове при стартиране.
  //
  // При съществуващ акаунт липсващите локални ключове трябва
  // да бъдат възстановени или създадени чрез изрично действие,
  // а не автоматично при отваряне на приложението.
  //
  // Новата идентичност се създава в регистрационния поток.
  // Не променяме публичния ключ в Supabase при стартиране.
  //
  // MLS identity се зарежда след login (loadIdentityFromStorage),
  // не тук при студено стартиране без сесия.

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
