import 'package:flutter/material.dart';

import '../../core/auth/auth_service.dart';
import '../../core/theme/criptivo_theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();

  bool _isLoading = false;
  bool _isSignUp = true;
  String? _message;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      setState(() => _message = 'Попълни email и парола');
      return;
    }

    if (_isSignUp && _usernameController.text.trim().isEmpty) {
      setState(() => _message = 'Попълни username');
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      if (_isSignUp) {
        await AuthService.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          username: _usernameController.text.trim(),
        );
        if (!mounted) return;
        setState(() {
          _message = 'Регистрацията е успешна! Провери имейла си.';
        });
      } else {
        await AuthService.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        // AuthGate вече сменя екрана — без setState за успех
        if (!mounted) return;
      }
    } catch (e) {
      print('Login error: $e');
      if (!mounted) return;
      setState(() => _message = 'Грешка: $e');
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/criptivo_logo.png',
                    height: 140,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
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
                    TextField(
                      controller: _usernameController,
                      style: const TextStyle(color: CriptivoColors.textPrimary),
                      decoration: const InputDecoration(labelText: 'Username'),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                  ],

                  TextField(
                    controller: _emailController,
                    style: const TextStyle(color: CriptivoColors.textPrimary),
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    style: const TextStyle(color: CriptivoColors.textPrimary),
                    decoration: const InputDecoration(labelText: 'Password'),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
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
                            child: Text(_isSignUp ? 'Регистрация' : 'Вход'),
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
                        color: _message!.startsWith('Грешка')
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
    );
  }
}
