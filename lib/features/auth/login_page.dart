import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_service.dart';
import '../../core/theme/criptivo_theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();

  bool _isLoading = false;
  bool _isSignUp = true;
  bool _obscurePassword = true;
  String? _message;
  bool _messageIsError = false;

  static final _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
  );
  static final _usernameRegex = RegExp(r'^[a-zA-Z0-9_]{3,20}$');

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Въведи email';
    if (!_emailRegex.hasMatch(v)) return 'Невалиден email';
    return null;
  }

  String? _validatePassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Въведи парола';
    if (v.length < 8) return 'Паролата трябва да е поне 8 символа';
    return null;
  }

  String? _validateUsername(String? value) {
    if (!_isSignUp) return null;
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Въведи username';
    if (!_usernameRegex.hasMatch(v)) {
      return '3–20 символа: букви, цифри, _';
    }
    return null;
  }

  String _friendlyError(Object e) {
    // От AuthService (зает username, липсващи ключове и т.н.)
    if (e is StateError) {
      return e.message;
    }

    if (e is AuthException) {
      final msg = e.message.toLowerCase();
      if (msg.contains('invalid login') ||
          msg.contains('invalid credentials')) {
        return 'Грешен email или парола';
      }
      if (msg.contains('email not confirmed')) {
        return 'Потвърди email адреса си преди вход';
      }
      if (msg.contains('user already registered') ||
          msg.contains('already been registered')) {
        return 'Този email вече е регистриран';
      }
      if (msg.contains('password')) {
        return 'Паролата не отговаря на изискванията (мин. 8 символа)';
      }
      if (msg.contains('rate limit') || msg.contains('too many')) {
        return 'Твърде много опити. Изчакай малко.';
      }
      return 'Грешка при удостоверяване. Опитай отново.';
    }

    final s = e.toString().toLowerCase();
    if (s.contains('network') || s.contains('socket')) {
      return 'Няма връзка с мрежата';
    }
    if (s.contains('duplicate') || s.contains('unique')) {
      return 'Този username вече е зает';
    }
    return 'Нещо се обърка. Опитай отново.';
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      if (_isSignUp) {
        await AuthService.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          username: _usernameController.text.trim().toLowerCase(),
        );
        if (!mounted) return;
        setState(() {
          _message =
              'Регистрацията е успешна! Провери имейла си за потвърждение.';
          _messageIsError = false;
          _isSignUp = false;
        });
      } else {
        await AuthService.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        // AuthGate сменя екрана
      }
    } catch (e) {
      debugPrint('Login error: $e');
      if (!mounted) return;
      setState(() {
        _message = _friendlyError(e);
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CriptivoColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/criptivo_logo.png',
                      height: 140,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) {
                        return const Text(
                          'CRIPTIVO',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: CriptivoColors.neon,
                            letterSpacing: 6,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isSignUp ? 'Създай акаунт' : 'Вход',
                      style: const TextStyle(
                        color: CriptivoColors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 32),

                    if (_isSignUp) ...[
                      TextFormField(
                        controller: _usernameController,
                        style: const TextStyle(
                          color: CriptivoColors.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        validator: _validateUsername,
                      ),
                      const SizedBox(height: 12),
                    ],

                    TextFormField(
                      controller: _emailController,
                      style: const TextStyle(
                        color: CriptivoColors.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      validator: _validateEmail,
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: const TextStyle(
                        color: CriptivoColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () {
                            setState(
                              () => _obscurePassword = !_obscurePassword,
                            );
                          },
                        ),
                      ),
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      validator: _validatePassword,
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: _isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: CriptivoColors.neon,
                              ),
                            )
                          : ElevatedButton(
                              onPressed: _submit,
                              child: Text(
                                _isSignUp ? 'Регистрация' : 'Вход',
                              ),
                            ),
                    ),
                    const SizedBox(height: 12),

                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              setState(() {
                                _isSignUp = !_isSignUp;
                                _message = null;
                                _formKey.currentState?.reset();
                              });
                            },
                      child: Text(
                        _isSignUp
                            ? 'Вече имаш акаунт? Влез'
                            : 'Нямаш акаунт? Регистрирай се',
                      ),
                    ),

                    if (_message != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _messageIsError
                              ? CriptivoColors.error
                              : CriptivoColors.neon,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
